import BroadCore
import Foundation

public enum RUCheckoutFlowOutcome: Equatable, Sendable {
    /// The external page opened and a pending context was persisted. This is not
    /// an entitlement and must never unlock premium by itself.
    case opened(PendingRUCheckoutContext)
    case unavailable(AppError)
    case failed(AppError)
}

actor RUCheckoutFlowCoordinator {
    private let checkout: any CreateRUCheckoutUseCaseProtocol
    private let authorizationProvider: any SubjectAuthorizationProviderProtocol
    private let storefrontRepository: any LiveStorefrontRepositoryProtocol
    private let gate: RUBillingGate
    private let opener: any PaymentURLOpenerProtocol
    private let pendingStore: any PendingRUCheckoutStoreProtocol
    private let analytics: (any MonetizationAnalyticsProtocol)?
    private let operationGate: MonetizationOperationGate
    private let clock: CacheClock
    private let minimumSessionValidity: TimeInterval

    private var isStarting = false
    private var queuedAnalyticsEvents: [MonetizationAnalyticsEvent] = []
    private var isDrainingAnalytics = false

    init(
        checkout: any CreateRUCheckoutUseCaseProtocol,
        authorizationProvider: any SubjectAuthorizationProviderProtocol,
        storefrontRepository: any LiveStorefrontRepositoryProtocol,
        gate: RUBillingGate,
        opener: any PaymentURLOpenerProtocol,
        pendingStore: any PendingRUCheckoutStoreProtocol,
        analytics: (any MonetizationAnalyticsProtocol)? = nil,
        operationGate: MonetizationOperationGate,
        clock: CacheClock = .system,
        minimumSessionValidity: TimeInterval = 30
    ) {
        precondition(
            minimumSessionValidity.isFinite && minimumSessionValidity >= 0,
            "RU checkout minimum session validity must be finite and non-negative"
        )
        self.checkout = checkout
        self.authorizationProvider = authorizationProvider
        self.storefrontRepository = storefrontRepository
        self.gate = gate
        self.opener = opener
        self.pendingStore = pendingStore
        self.analytics = analytics.map(NonBlockingMonetizationAnalytics.wrapping)
        self.operationGate = operationGate
        self.clock = clock
        self.minimumSessionValidity = minimumSessionValidity
        operationGate.registerPendingOperationBlocker(pendingStore)
    }

    func start(
        _ request: RUCheckoutRequest,
        selection: ProductSelection,
        remoteConfiguration: RemotePaywallConfiguration
    ) async -> RUCheckoutFlowOutcome {
        guard !isStarting else {
            return .unavailable(RUBillingSafeErrors.checkoutUnavailable)
        }

        isStarting = true
        defer { isStarting = false }

        guard let lease = await operationGate.acquire(.ruCheckout) else {
            return .unavailable(RUBillingSafeErrors.checkoutUnavailable)
        }

        let outcome = await performStart(
            request,
            selection: selection,
            remoteConfiguration: remoteConfiguration
        )
        await operationGate.release(lease)
        return outcome
    }
}

private extension RUCheckoutFlowCoordinator {
    func performStart(
        _ request: RUCheckoutRequest,
        selection: ProductSelection,
        remoteConfiguration: RemotePaywallConfiguration
    ) async -> RUCheckoutFlowOutcome {
        if let eligibilityError = await eligibilityError(
            remoteConfiguration: remoteConfiguration
        ) {
            return .unavailable(eligibilityError)
        }

        let attemptID = MonetizationAttemptID.generated()
        let analyticsContext = RUCheckoutAnalyticsContext(
            attemptID: attemptID,
            selection: selection,
            productID: request.productID,
            checkoutMethod: request.method
        )

        switch await checkout(request) {
        case let .created(session, authorizationProof):
            guard await authorizationProvider.stillOwns(
                authorizationProof
            ) else {
                return .unavailable(RUBillingSafeErrors.checkoutUnavailable)
            }
            return await openPaymentPage(
                session: session,
                request: request,
                analyticsContext: analyticsContext,
                authorizationProof: authorizationProof
            )
        case let .unavailable(error):
            return .unavailable(error)
        case let .failed(error):
            return .failed(error)
        }
    }

    func eligibilityError(
        remoteConfiguration: RemotePaywallConfiguration
    ) async -> AppError? {
        guard gate.mayBeEligible(remoteConfiguration: remoteConfiguration) else {
            return RUBillingSafeErrors.checkoutNotEligible
        }
        guard case let .available(storefront) =
            await storefrontRepository.liveCurrentStorefront()
        else {
            return RUBillingSafeErrors.storefrontUnavailable
        }
        guard gate.allows(
            remoteConfiguration: remoteConfiguration,
            storefront: storefront
        ) else {
            return RUBillingSafeErrors.checkoutNotEligible
        }
        return nil
    }

    func openPaymentPage(
        session: RUCheckoutSession,
        request: RUCheckoutRequest,
        analyticsContext: RUCheckoutAnalyticsContext,
        authorizationProof: SubjectAuthorizationProof
    ) async -> RUCheckoutFlowOutcome {
        guard await authorizationProvider.stillOwns(
            authorizationProof
        ) else {
            return .unavailable(RUBillingSafeErrors.checkoutUnavailable)
        }

        let startedAt = clock.now()
        let minimumExpiration = startedAt.timeIntervalSinceReferenceDate
            + minimumSessionValidity
        guard startedAt.timeIntervalSinceReferenceDate.isFinite,
              minimumExpiration.isFinite,
              session.expiresAt.map({
                  $0.timeIntervalSinceReferenceDate > minimumExpiration
              }) ?? true
        else {
            return .unavailable(RUBillingSafeErrors.checkoutUnavailable)
        }

        let context = pendingContext(
            session: session,
            request: request,
            analyticsContext: analyticsContext,
            startedAt: startedAt
        )
        enqueueAnalytics(.ruCheckoutCreated(analyticsContext))
        guard await pendingStore.save(context) else {
            return .unavailable(RUBillingSafeErrors.checkoutUnavailable)
        }
        // Persistence is an await boundary. If logout, account switch or token
        // rotation happened while it was in flight, retain the old subject's
        // blocker but never expose the payment page under the new identity.
        guard await authorizationProvider.stillOwns(
            authorizationProof
        ) else {
            return .unavailable(RUBillingSafeErrors.checkoutUnavailable)
        }
        guard await opener.open(session.paymentURL) else {
            let error = RUBillingSafeErrors.paymentPageOpenFailed
            enqueueAnalytics(
                .ruCheckoutOpenFailed(
                    analyticsContext,
                    failure: MonetizationAnalyticsFailure(error: error)
                )
            )
            return await pendingStore.clear(
                checkoutSessionID: context.checkoutSessionID,
                attemptID: context.attemptID
            )
                ? .failed(error)
                : .unavailable(RUBillingSafeErrors.checkoutUnavailable)
        }
        return .opened(context)
    }

    func pendingContext(
        session: RUCheckoutSession,
        request: RUCheckoutRequest,
        analyticsContext: RUCheckoutAnalyticsContext,
        startedAt: Date
    ) -> PendingRUCheckoutContext {
        PendingRUCheckoutContext(
            checkoutSessionID: session.id,
            attemptID: analyticsContext.attemptID,
            productID: request.productID,
            checkoutMethod: request.method,
            paywallPresentationID: analyticsContext.paywallPresentationID,
            paywallVariationID: analyticsContext.paywallVariationID,
            requestedPlacementID: analyticsContext.requestedPlacementID,
            resolvedPlacementID: analyticsContext.resolvedPlacementID,
            startedAt: startedAt,
            expiresAt: session.expiresAt
        )
    }

    func enqueueAnalytics(_ event: MonetizationAnalyticsEvent) {
        guard analytics != nil else {
            return
        }

        queuedAnalyticsEvents.append(event)
        guard !isDrainingAnalytics else {
            return
        }

        isDrainingAnalytics = true
        Task { [weak self] in
            await self?.drainAnalyticsQueue()
        }
    }

    func drainAnalyticsQueue() async {
        guard let analytics else {
            queuedAnalyticsEvents = []
            isDrainingAnalytics = false
            return
        }

        while !queuedAnalyticsEvents.isEmpty {
            let event = queuedAnalyticsEvents.removeFirst()
            await analytics.track(event)
        }

        isDrainingAnalytics = false
    }
}
