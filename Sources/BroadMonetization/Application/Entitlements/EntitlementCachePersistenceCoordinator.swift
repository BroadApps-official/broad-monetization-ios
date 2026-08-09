actor EntitlementCachePersistenceCoordinator {
    private let cache: any EntitlementCacheProtocol
    private var states: [EntitlementCacheScope: WriteState] = [:]

    init(cache: any EntitlementCacheProtocol) {
        self.cache = cache
    }

    func schedule(
        assertions: [EntitlementSource: EntitlementSourceAssertion],
        scopes: [EntitlementSource: EntitlementCacheScope],
        generation: UInt64
    ) {
        for (source, assertion) in assertions {
            guard let scope = scopes[source] else {
                continue
            }
            schedule(
                PendingWrite(
                    assertion: assertion,
                    generation: generation
                ),
                for: scope
            )
        }
    }

    private func schedule(
        _ pendingWrite: PendingWrite,
        for scope: EntitlementCacheScope
    ) {
        var state = states[scope] ?? WriteState()
        guard pendingWrite.generation >= state.latestGeneration else {
            return
        }

        state.latestGeneration = pendingWrite.generation
        if state.isWriting {
            state.pendingWrite = pendingWrite
            states[scope] = state
            return
        }

        state.isWriting = true
        states[scope] = state
        start(pendingWrite, for: scope)
    }

    private func start(
        _ pendingWrite: PendingWrite,
        for scope: EntitlementCacheScope
    ) {
        let cache = cache
        Task {
            try? await cache.write(
                pendingWrite.assertion,
                for: scope
            )
            writeCompleted(for: scope)
        }
    }

    private func writeCompleted(
        for scope: EntitlementCacheScope
    ) {
        guard var state = states[scope] else {
            return
        }

        if let pendingWrite = state.pendingWrite {
            state.pendingWrite = nil
            states[scope] = state
            start(pendingWrite, for: scope)
            return
        }

        state.isWriting = false
        states[scope] = state
    }
}

private extension EntitlementCachePersistenceCoordinator {
    struct PendingWrite: Sendable {
        let assertion: EntitlementSourceAssertion
        let generation: UInt64
    }

    struct WriteState {
        var isWriting = false
        var latestGeneration: UInt64 = 0
        var pendingWrite: PendingWrite?
    }
}
