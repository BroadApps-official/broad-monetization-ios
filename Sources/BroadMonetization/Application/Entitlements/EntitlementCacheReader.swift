import Foundation

struct EntitlementCacheReader: Sendable {
    let gate: EntitlementCacheReadGate

    func read(
        before deadline: ContinuousClock.Instant
    ) async -> EntitlementSourceAssertion? {
        let waiterID = UUID()
        let race = EntitlementCacheReadRace()
        let operationTask = Task {
            let assertion = await gate.read(waiterID: waiterID)
            await race.resolve(.value(assertion))
        }
        let timeoutTask = Task {
            do {
                try await ContinuousClock().sleep(until: deadline)
                await race.resolve(.timedOut)
            } catch {
                // The cache read won the race or the caller was cancelled.
            }
        }

        let outcome = await withTaskCancellationHandler {
            await race.value()
        } onCancel: {
            operationTask.cancel()
            timeoutTask.cancel()
            Task {
                await race.resolve(.timedOut)
            }
        }

        await gate.cancelWaiter(waiterID)
        operationTask.cancel()
        timeoutTask.cancel()

        guard case let .value(assertion) = outcome else {
            return nil
        }
        return assertion
    }
}

actor EntitlementCacheReadGate {
    private let cache: any EntitlementCacheProtocol
    private let scope: EntitlementCacheScope
    private var generation: UInt64 = 0
    private var inFlight: InFlight?
    private var acceptsNewWaiters = false
    private var waiters: [UUID: CheckedContinuation<EntitlementSourceAssertion?, Never>] = [:]

    init(
        cache: any EntitlementCacheProtocol,
        scope: EntitlementCacheScope
    ) {
        self.cache = cache
        self.scope = scope
    }

    func read(
        waiterID: UUID
    ) async -> EntitlementSourceAssertion? {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(returning: nil)
                    return
                }

                guard inFlight == nil || acceptsNewWaiters else {
                    continuation.resume(returning: nil)
                    return
                }

                waiters[waiterID] = continuation
                startReadIfNeeded()
            }
        } onCancel: {
            Task {
                await self.cancelWaiter(waiterID)
            }
        }
    }

    func cancelWaiter(_ waiterID: UUID) {
        guard let continuation = waiters.removeValue(forKey: waiterID) else {
            return
        }

        continuation.resume(returning: nil)
        if waiters.isEmpty {
            acceptsNewWaiters = false
        }
    }

    private func startReadIfNeeded() {
        guard inFlight == nil else {
            return
        }

        generation &+= 1
        let currentGeneration = generation
        let cache = cache
        let scope = scope
        acceptsNewWaiters = true
        let task = Task {
            let assertion = try? await cache.read(for: scope)
            complete(
                assertion,
                generation: currentGeneration
            )
        }
        inFlight = InFlight(
            generation: currentGeneration,
            task: task
        )
    }

    private func complete(
        _ assertion: EntitlementSourceAssertion?,
        generation: UInt64
    ) {
        guard inFlight?.generation == generation else {
            return
        }

        inFlight = nil
        acceptsNewWaiters = false
        let continuations = Array(waiters.values)
        waiters.removeAll()
        for continuation in continuations {
            continuation.resume(returning: assertion)
        }
    }
}

private extension EntitlementCacheReadGate {
    struct InFlight {
        let generation: UInt64
        let task: Task<Void, Never>
    }
}

private enum EntitlementCacheReadOutcome: Sendable {
    case value(EntitlementSourceAssertion?)
    case timedOut
}

private actor EntitlementCacheReadRace {
    private var result: EntitlementCacheReadOutcome?
    private var continuation: CheckedContinuation<EntitlementCacheReadOutcome, Never>?

    func resolve(_ result: EntitlementCacheReadOutcome) {
        guard self.result == nil else {
            return
        }

        self.result = result
        continuation?.resume(returning: result)
        continuation = nil
    }

    func value() async -> EntitlementCacheReadOutcome {
        if let result {
            return result
        }

        return await withCheckedContinuation { continuation in
            precondition(
                self.continuation == nil,
                "Entitlement cache read race supports one waiter"
            )
            self.continuation = continuation
        }
    }
}
