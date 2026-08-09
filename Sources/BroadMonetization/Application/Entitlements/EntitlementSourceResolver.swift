import Foundation

struct EntitlementSourceResolver: Sendable {
    let runtime: EntitlementSourceRuntime
    let refreshGeneration: UInt64
    let forceNewGeneration: Bool

    func resolve(
        before deadline: ContinuousClock.Instant
    ) async -> EntitlementSourceResolution {
        let waiterID = UUID()
        let race = EntitlementSourceResolutionRace()
        let operationTask = Task {
            let result = await runtime.executionGate.resolve(
                waiterID: waiterID,
                refreshGeneration: refreshGeneration,
                forceNewGeneration: forceNewGeneration
            )
            await race.resolve(result)
        }
        let timeoutTask = Task {
            do {
                try await ContinuousClock().sleep(until: deadline)
                await race.resolve(.unresolved)
            } catch {
                // The source won the race or the caller was cancelled.
            }
        }

        let result = await withTaskCancellationHandler {
            await race.value()
        } onCancel: {
            operationTask.cancel()
            timeoutTask.cancel()
            Task {
                await race.resolve(.unresolved)
            }
        }

        await runtime.executionGate.cancelWaiter(waiterID)
        operationTask.cancel()
        timeoutTask.cancel()
        return result
    }
}

private actor EntitlementSourceResolutionRace {
    private var result: EntitlementSourceResolution?
    private var continuation: CheckedContinuation<EntitlementSourceResolution, Never>?

    func resolve(_ result: EntitlementSourceResolution) {
        guard self.result == nil else {
            return
        }

        self.result = result
        continuation?.resume(returning: result)
        continuation = nil
    }

    func value() async -> EntitlementSourceResolution {
        if let result {
            return result
        }

        return await withCheckedContinuation { continuation in
            precondition(
                self.continuation == nil,
                "Entitlement resolution race supports one waiter"
            )
            self.continuation = continuation
        }
    }
}
