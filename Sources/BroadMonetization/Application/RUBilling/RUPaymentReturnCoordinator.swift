public enum RUPaymentReturnOutcome: Equatable, Sendable {
    case noPendingCheckout
    case active(EntitlementSnapshot)
    case pending
    case inactive
    case unavailable
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

    private var returnedAttempts: Set<MonetizationAttemptID> = []
    private var timedOutAttempts: Set<MonetizationAttemptID> = []
    private var pendingReadOperation: PendingReadOperation?
    private var returnOperations: [MonetizationAttemptID: ReturnOperation] = [:]
    private var operationGeneration: UInt64 = 0

    init(
        pendingStore: any PendingRUCheckoutStoreProtocol,
        refreshPayment: any RefreshRUPaymentUseCaseProtocol,
        operationGate: MonetizationOperationGate,
        analytics: (any MonetizationAnalyticsProtocol)? = nil
    ) {
        self.pendingStore = pendingStore
        self.refreshPayment = refreshPayment
        self.operationGate = operationGate
        self.analytics = analytics.map(NonBlockingMonetizationAnalytics.wrapping)
    }

    /// The host calls this only after the application becomes active again.
    /// An opened payment page alone never reaches this method and never grants access.
    public func applicationDidBecomeActive() async -> RUPaymentReturnOutcome {
        let context: PendingRUCheckoutContext
        switch await readPendingState() {
        case .none:
            return .noPendingCheckout
        case .blockedByAnotherSubject, .unavailable:
            return .unavailable
        case let .pending(value):
            context = value
        }

        if let operation = returnOperations[context.attemptID] {
            return await operation.task.value
        }

        let generation = nextOperationGeneration()
        let task = Task { [weak self] in
            guard let self else {
                return RUPaymentReturnOutcome.unavailable
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

        switch await refreshPayment(checkoutSessionID: context.checkoutSessionID) {
        case let .active(snapshot):
            guard await pendingStore.clear(
                checkoutSessionID: context.checkoutSessionID,
                attemptID: context.attemptID
            ) else {
                return .unavailable
            }
            await operationGate.notifyFinancialOperationStateChanged()
            await analytics?.track(.ruCheckoutConfirmed(context.analyticsContext))
            return .active(snapshot)
        case .pending:
            await trackTimedOutIfNeeded(context)
            return .pending
        case .inactive:
            guard await pendingStore.clear(
                checkoutSessionID: context.checkoutSessionID,
                attemptID: context.attemptID
            ) else {
                return .unavailable
            }
            await operationGate.notifyFinancialOperationStateChanged()
            return .inactive
        case .unavailable:
            await trackTimedOutIfNeeded(context)
            return .unavailable
        }
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
