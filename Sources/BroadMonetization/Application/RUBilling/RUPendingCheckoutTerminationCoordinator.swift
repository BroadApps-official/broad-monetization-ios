import BroadCore

/// Ends an abandoned checkout only through backend-authoritative termination.
public actor RUPendingCheckoutTerminationCoordinator {
    private struct PendingReadOperation {
        let generation: UInt64
        let task: Task<PendingRUCheckoutState, Never>
    }

    private struct TerminationOperation {
        let generation: UInt64
        let task: Task<RUPendingCheckoutTerminationOutcome, Never>
    }

    private let pendingStore: any PendingRUCheckoutStoreProtocol
    private let client: (any RUCheckoutTerminationClientProtocol)?
    private let operationGate: MonetizationOperationGate

    private var pendingReadOperation: PendingReadOperation?
    private var terminationOperations: [MonetizationAttemptID: TerminationOperation] = [:]
    private var operationGeneration: UInt64 = 0

    init(
        pendingStore: any PendingRUCheckoutStoreProtocol,
        client: (any RUCheckoutTerminationClientProtocol)?,
        operationGate: MonetizationOperationGate
    ) {
        self.pendingStore = pendingStore
        self.client = client
        self.operationGate = operationGate
    }

    /// Call only after explicit user intent to abandon the checkout. A terminal
    /// backend result clears the exact durable attempt and releases the shared
    /// financial-operation gate. Every uncertain result remains blocked.
    public func terminatePendingCheckout() async -> RUPendingCheckoutTerminationOutcome {
        let context: PendingRUCheckoutContext
        switch await readPendingState() {
        case .none:
            return .noPendingCheckout
        case .blockedByAnotherSubject, .unavailable:
            return .unavailable(RUBillingSafeErrors.pendingCheckoutTerminationUnavailable)
        case let .pending(value):
            context = value
        }

        guard client != nil else {
            return .unavailable(RUBillingSafeErrors.pendingCheckoutTerminationUnavailable)
        }
        if let operation = terminationOperations[context.attemptID] {
            return await operation.task.value
        }

        let generation = nextOperationGeneration()
        let task = Task { [weak self] in
            guard let self else {
                return RUPendingCheckoutTerminationOutcome.unavailable(
                    RUBillingSafeErrors.pendingCheckoutTerminationUnavailable
                )
            }
            return await resolveTermination(for: context)
        }
        terminationOperations[context.attemptID] = TerminationOperation(
            generation: generation,
            task: task
        )

        let outcome = await task.value
        if terminationOperations[context.attemptID]?.generation == generation {
            terminationOperations[context.attemptID] = nil
        }
        return outcome
    }
}

private extension RUPendingCheckoutTerminationCoordinator {
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

    func resolveTermination(
        for context: PendingRUCheckoutContext
    ) async -> RUPendingCheckoutTerminationOutcome {
        guard let client else {
            return .unavailable(
                RUBillingSafeErrors.pendingCheckoutTerminationUnavailable
            )
        }
        let request = RUPendingCheckoutTerminationRequest(
            checkoutSessionID: context.checkoutSessionID,
            attemptID: context.attemptID,
            productID: context.productID,
            checkoutMethod: context.checkoutMethod
        )

        switch await client.terminatePendingCheckout(request) {
        case let .terminated(status):
            guard await pendingStore.clear(
                checkoutSessionID: context.checkoutSessionID,
                attemptID: context.attemptID
            ) else {
                return .unavailable(
                    RUBillingSafeErrors.pendingCheckoutTerminationUnavailable
                )
            }
            await operationGate.notifyFinancialOperationStateChanged()
            return .terminated(status)
        case .pending:
            return .pending
        case let .unavailable(error):
            return .unavailable(error)
        }
    }

    func nextOperationGeneration() -> UInt64 {
        operationGeneration &+= 1
        return operationGeneration
    }
}
