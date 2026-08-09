public struct AppleEntitlementRepository: EntitlementSourceRepositoryProtocol {
    private let verifiers: [any AppleEntitlementVerifierProtocol]

    public init(verifiers: [any AppleEntitlementVerifierProtocol]) {
        precondition(
            !verifiers.isEmpty,
            "Apple entitlement repository needs at least one enabled verifier"
        )
        self.verifiers = verifiers
    }

    public func resolveEntitlement(
        for subject: EntitlementSubject
    ) async -> EntitlementSourceResolution {
        let operation = AppleEntitlementVerificationOperation(
            verifiers: verifiers,
            subject: subject
        )
        return await operation.resolve()
    }
}

private actor AppleEntitlementVerificationOperation {
    private let verifiers: [any AppleEntitlementVerifierProtocol]
    private let subject: EntitlementSubject

    private var tasks: [Task<Void, Never>] = []
    private var continuation: CheckedContinuation<EntitlementSourceResolution, Never>?
    private var completedResolutions: [EntitlementSourceResolution] = []
    private var isFinished = false

    init(
        verifiers: [any AppleEntitlementVerifierProtocol],
        subject: EntitlementSubject
    ) {
        self.verifiers = verifiers
        self.subject = subject
    }

    func resolve() async -> EntitlementSourceResolution {
        await withTaskCancellationHandler {
            guard !Task.isCancelled else {
                return .unresolved
            }

            let resolution = await withCheckedContinuation { continuation in
                self.continuation = continuation
                startVerifiers()
            }
            return Task.isCancelled ? .unresolved : resolution
        } onCancel: {
            Task {
                await self.cancel()
            }
        }
    }

    private func startVerifiers() {
        for verifier in verifiers {
            let task = Task {
                let resolution = await verifier.verifyEntitlement(for: subject)
                accept(resolution)
            }
            tasks.append(task)
        }
    }

    private func accept(_ resolution: EntitlementSourceResolution) {
        guard !isFinished else {
            return
        }

        completedResolutions.append(resolution)

        if case .active = resolution {
            finish(with: aggregateActiveResolution())
            return
        }

        guard completedResolutions.count == verifiers.count else {
            return
        }

        let resolution: EntitlementSourceResolution = completedResolutions.allSatisfy {
            $0 == .inactive
        } ? .inactive : .unresolved
        finish(with: resolution)
    }

    private func aggregateActiveResolution() -> EntitlementSourceResolution {
        let activeValidities: [EntitlementActiveValidity] = completedResolutions.compactMap { resolution in
            guard case let .active(validity) = resolution else {
                return nil
            }
            return validity
        }

        if activeValidities.contains(.lifetime) {
            return .active(.lifetime)
        }
        if activeValidities.contains(.unspecified) {
            return .active(.unspecified)
        }

        let expiration = activeValidities.compactMap(\.expirationDate).max()
        return .active(expiration.map { .expires(at: $0) } ?? .unspecified)
    }

    private func cancel() {
        finish(with: .unresolved)
    }

    private func finish(with resolution: EntitlementSourceResolution) {
        guard !isFinished else {
            return
        }

        isFinished = true
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        continuation?.resume(returning: resolution)
        continuation = nil
    }
}
