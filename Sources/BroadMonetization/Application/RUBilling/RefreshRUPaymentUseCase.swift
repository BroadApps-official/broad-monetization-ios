import BroadCore

public struct RUPaymentPollingPolicy: Equatable, Sendable {
    public let maximumAttempts: Int
    public let delay: Duration

    public init(
        maximumAttempts: Int = 8,
        delay: Duration = .seconds(2)
    ) {
        precondition(maximumAttempts > 0, "RU payment polling attempts must be positive")
        precondition(delay >= .zero, "RU payment polling delay must not be negative")
        self.maximumAttempts = maximumAttempts
        self.delay = delay
    }
}

struct RefreshRUPaymentUseCase: RefreshRUPaymentUseCaseProtocol {
    private let paymentStatusRepository: any RUPaymentStatusRepositoryProtocol
    private let refreshEntitlement: any RefreshEntitlementUseCaseProtocol
    private let policy: RUPaymentPollingPolicy
    private let authorizationBinding: SubjectAuthorizationBinding

    init(
        paymentStatusRepository: any RUPaymentStatusRepositoryProtocol,
        refreshEntitlement: any RefreshEntitlementUseCaseProtocol,
        authorizationBinding: SubjectAuthorizationBinding,
        policy: RUPaymentPollingPolicy = RUPaymentPollingPolicy()
    ) {
        self.paymentStatusRepository = paymentStatusRepository
        self.refreshEntitlement = refreshEntitlement
        self.authorizationBinding = authorizationBinding
        self.policy = policy
    }

    func callAsFunction(
        checkoutSessionID: CheckoutSessionID
    ) async -> RUPaymentRefreshOutcome {
        guard authorizationBinding.isCurrent() else {
            return .unavailable(RUBillingSafeErrors.paymentStatusUnavailable)
        }
        var sawResolvedPayment = false

        for attempt in 1 ... policy.maximumAttempts {
            guard operationMayContinue else {
                return .unavailable(RUBillingSafeErrors.paymentStatusUnavailable)
            }

            let paymentOutcome = await paymentStatusRepository.paymentStatus(
                for: checkoutSessionID
            )
            guard authorizationBinding.isCurrent() else {
                return .unavailable(RUBillingSafeErrors.paymentStatusUnavailable)
            }
            let resolution = await resolveAttempt(
                paymentOutcome,
                checkoutSessionID: checkoutSessionID
            )
            guard authorizationBinding.isCurrent() else {
                return .unavailable(RUBillingSafeErrors.paymentStatusUnavailable)
            }
            switch pollingDecision(for: resolution) {
            case let .finish(outcome):
                return outcome
            case let .continuePolling(isResolved):
                sawResolvedPayment = sawResolvedPayment || isResolved
            }

            if shouldDelay(after: attempt) {
                do {
                    try await ContinuousClock().sleep(for: policy.delay)
                } catch {
                    return .unavailable(RUBillingSafeErrors.paymentStatusUnavailable)
                }
            }
        }

        return sawResolvedPayment
            ? .pending
            : .unavailable(RUBillingSafeErrors.paymentStatusUnavailable)
    }

    var operationMayContinue: Bool {
        !Task.isCancelled && authorizationBinding.isCurrent()
    }

    func shouldDelay(after attempt: Int) -> Bool {
        attempt < policy.maximumAttempts && policy.delay > .zero
    }

    fileprivate func pollingDecision(
        for resolution: PaymentAttemptResolution
    ) -> PaymentPollingDecision {
        switch resolution {
        case let .active(snapshot):
            .finish(.active(snapshot))
        case .inactive:
            .finish(.inactive)
        case let .unavailable(error):
            .finish(.unavailable(error))
        case let .waiting(isResolved):
            .continuePolling(isResolved: isResolved)
        }
    }
}

private enum PaymentAttemptResolution {
    case active(EntitlementSnapshot)
    case inactive
    case unavailable(AppError)
    case waiting(isResolved: Bool)
}

private enum PaymentPollingDecision {
    case finish(RUPaymentRefreshOutcome)
    case continuePolling(isResolved: Bool)
}

private extension RefreshRUPaymentUseCase {
    func resolveAttempt(
        _ outcome: RUPaymentStatusOutcome,
        checkoutSessionID: CheckoutSessionID
    ) async -> PaymentAttemptResolution {
        guard case let .resolved(payment) = outcome else {
            if case let .unavailable(error) = outcome,
               error.kind == .offline || error.kind == .timeout {
                return .unavailable(error)
            }
            return .waiting(isResolved: false)
        }
        guard payment.checkoutSessionID == checkoutSessionID else {
            return .waiting(isResolved: false)
        }

        switch payment.status {
        case .paid:
            guard authorizationBinding.isCurrent() else {
                return .waiting(isResolved: false)
            }
            let entitlement = await refreshEntitlement(
                policy: .startNewGeneration
            )
            guard authorizationBinding.isCurrent() else {
                return .waiting(isResolved: false)
            }
            return entitlement.confirmsRUPaymentAccess
                ? .active(entitlement)
                : .waiting(isResolved: true)
        case .failed, .cancelled, .expired:
            return .inactive
        case .pending:
            return .waiting(isResolved: true)
        }
    }
}

private extension EntitlementSnapshot {
    var confirmsRUPaymentAccess: Bool {
        sources.contains { source in
            let isRUPaymentAuthority = source.source == .primaryBackend || source.source == .ruBilling
            return isRUPaymentAuthority
                && source.state == .active
                && source.freshness == .refreshed
        }
    }
}
