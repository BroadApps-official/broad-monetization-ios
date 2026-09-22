import BroadCore

public enum RUPaymentReturnOutcome: Equatable, Sendable {
    case noPendingCheckout
    case active(EntitlementSnapshot)
    /// Fresh account balance increased. Does not grant subscription access.
    case tokensCredited(Int)
    case pending
    /// Account-policy waiting ended without confirmation. Retry is allowed;
    /// the existing payment link may still settle later.
    case waitingCompleted
    case inactive
    case unavailable(AppError)
}

public actor RUPaymentReturnCoordinator {
    private struct PendingReadOperation {
        let generation: UInt64
        let task: Task<PendingRUCheckoutState, Never>
    }

    private struct ReturnOperation {
        let generation: UInt64
        let task: Task<RUPaymentReturnOutcome, Never>
    }

    private let pendingStore: any PendingRUCheckoutStoreProtocol
    private let refreshPayment: any RefreshRUPaymentUseCaseProtocol
    private let operationGate: MonetizationOperationGate
    private let analytics: (any MonetizationAnalyticsProtocol)?
    private let usesAccountPolicy: Bool

    private var returnedAttempts: Set<MonetizationAttemptID> = []
    private var timedOutAttempts: Set<MonetizationAttemptID> = []
    private var pendingReadOperation: PendingReadOperation?
    private var returnOperations: [MonetizationAttemptID: ReturnOperation] = [:]
    private var operationGeneration: UInt64 = 0

    init(
        pendingStore: any PendingRUCheckoutStoreProtocol,
        refreshPayment: any RefreshRUPaymentUseCaseProtocol,
        operationGate: MonetizationOperationGate,
        analytics: (any MonetizationAnalyticsProtocol)? = nil,
        usesAccountPolicy: Bool = false
    ) {
        self.pendingStore = pendingStore
        self.refreshPayment = refreshPayment
        self.operationGate = operationGate
        self.analytics = analytics.map(NonBlockingMonetizationAnalytics.wrapping)
        self.usesAccountPolicy = usesAccountPolicy
    }

    /// Call after foreground return or embedded payment-page dismissal.
    /// An opened payment page alone never reaches this method and never grants access.
    public func applicationDidBecomeActive() async -> RUPaymentReturnOutcome {
        let context: PendingRUCheckoutContext
        switch await readPendingState() {
        case .none:
            return .noPendingCheckout
        case .blockedByAnotherSubject, .unavailable:
            return .unavailable(RUBillingSafeErrors.paymentStatusUnavailable)
        case let .pending(value), let .awaitingReconciliation(value):
            context = value
        }

        if let operation = returnOperations[context.attemptID] {
            return await operation.task.value
        }

        let generation = nextOperationGeneration()
        let task = Task { [weak self] in
            guard let self else {
                return RUPaymentReturnOutcome.unavailable(
                    RUBillingSafeErrors.paymentStatusUnavailable
                )
            }
            return await resolveReturn(for: context)
        }
        returnOperations[context.attemptID] = ReturnOperation(
            generation: generation,
            task: task
        )

        let outcome = await task.value
        if returnOperations[context.attemptID]?.generation == generation {
            returnOperations[context.attemptID] = nil
        }
        return outcome
    }
}

private extension RUPaymentReturnCoordinator {
    func readPendingState() async -> PendingRUCheckoutState {
        if let operation = pendingReadOperation {
            return await operation.task.value
        }

        let generation = nextOperationGeneration()
        let store = pendingStore
        let task = Task {
            await store.state()
        }
        pendingReadOperation = PendingReadOperation(
            generation: generation,
            task: task
        )

        let state = await task.value
        if pendingReadOperation?.generation == generation {
            pendingReadOperation = nil
        }
        return state
    }

    func resolveReturn(
        for context: PendingRUCheckoutContext
    ) async -> RUPaymentReturnOutcome {
        if returnedAttempts.insert(context.attemptID).inserted {
            await analytics?.track(.ruCheckoutSafariReturned(context.analyticsContext))
        }

        switch await refreshPayment(
            checkoutSessionID: context.checkoutSessionID,
            productID: context.productID,
            accountExpectation: context.accountExpectation
        ) {
        case let .tokensCredited(balance):
            guard await pendingStore.clear(
                checkoutSessionID: context.checkoutSessionID,
                attemptID: context.attemptID
            ) else { return .unavailable(RUBillingSafeErrors.paymentStatusUnavailable) }
            await operationGate.notifyFinancialOperationStateChanged()
            await analytics?.track(.ruCheckoutConfirmed(context.analyticsContext))
            return .tokensCredited(balance)
        case let .active(snapshot):
            guard await pendingStore.clear(
                checkoutSessionID: context.checkoutSessionID,
                attemptID: context.attemptID
            ) else {
                return .unavailable(RUBillingSafeErrors.paymentStatusUnavailable)
            }
            await operationGate.notifyFinancialOperationStateChanged()
            await analytics?.track(.ruCheckoutConfirmed(context.analyticsContext))
            return .active(snapshot)
        case .pending:
            return await resolveUnconfirmed(context)
        case .inactive:
            guard await pendingStore.clear(
                checkoutSessionID: context.checkoutSessionID,
                attemptID: context.attemptID
            ) else {
                return .unavailable(
                    RUBillingSafeErrors.paymentStatusUnavailable
                )
            }
            await operationGate.notifyFinancialOperationStateChanged()
            return .inactive
        case let .unavailable(error):
            if usesAccountPolicy {
                _ = await finishWaiting(for: context)
            }
            await trackTimedOutIfNeeded(context)
            return .unavailable(error)
        }
    }

    func resolveUnconfirmed(_ context: PendingRUCheckoutContext) async -> RUPaymentReturnOutcome {
        if usesAccountPolicy {
            guard await finishWaiting(for: context) else {
                return .unavailable(RUBillingSafeErrors.paymentStatusUnavailable)
            }
            await trackTimedOutIfNeeded(context)
            return .waitingCompleted
        }
        await trackTimedOutIfNeeded(context)
        return .pending
    }

    func finishWaiting(for context: PendingRUCheckoutContext) async -> Bool {
        guard await pendingStore.finishWaiting(
            checkoutSessionID: context.checkoutSessionID, attemptID: context.attemptID
        ) else { return false }
        await operationGate.notifyFinancialOperationStateChanged()
        return true
    }

    func trackTimedOutIfNeeded(_ context: PendingRUCheckoutContext) async {
        guard timedOutAttempts.insert(context.attemptID).inserted else {
            return
        }
        await analytics?.track(.ruCheckoutTimedOut(context.analyticsContext))
    }

    func nextOperationGeneration() -> UInt64 {
        operationGeneration &+= 1
        return operationGeneration
    }
}
