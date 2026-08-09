import Foundation

public struct EntitlementSourceRegistration: Sendable {
    public let source: EntitlementSource
    public let subject: EntitlementSubject
    public let freshnessPolicy: EntitlementFreshnessPolicy

    let repository: any EntitlementSourceRepositoryProtocol
    let acceptanceGate: EntitlementSourceAcceptanceGate

    public init(
        source: EntitlementSource,
        subject: EntitlementSubject,
        freshnessPolicy: EntitlementFreshnessPolicy,
        repository: any EntitlementSourceRepositoryProtocol
    ) {
        self.init(
            source: source,
            subject: subject,
            freshnessPolicy: freshnessPolicy,
            repository: repository,
            acceptanceGate: .always
        )
    }

    init(
        source: EntitlementSource,
        subject: EntitlementSubject,
        freshnessPolicy: EntitlementFreshnessPolicy,
        repository: any EntitlementSourceRepositoryProtocol,
        acceptanceGate: EntitlementSourceAcceptanceGate
    ) {
        self.source = source
        self.subject = subject
        self.freshnessPolicy = freshnessPolicy
        self.repository = repository
        self.acceptanceGate = acceptanceGate
    }
}

struct EntitlementSourceAcceptanceGate: Sendable {
    static let always = EntitlementSourceAcceptanceGate(
        cachePartition: nil,
        cacheStoragePartition: nil,
        isCurrent: { true }
    )

    let cachePartition: String?
    let cacheStoragePartition: String?
    private let isCurrentValue: @Sendable () -> Bool

    init(
        cachePartition: String?,
        cacheStoragePartition: String?,
        isCurrent: @escaping @Sendable () -> Bool
    ) {
        precondition(
            (cachePartition == nil) == (cacheStoragePartition == nil),
            "Entitlement cache partitions must be both present or both absent"
        )
        self.cachePartition = cachePartition
        self.cacheStoragePartition = cacheStoragePartition
        isCurrentValue = isCurrent
    }

    func acceptsCurrentContext() -> Bool {
        isCurrentValue()
    }
}

struct EntitlementSourceRuntime: Sendable {
    let registration: EntitlementSourceRegistration
    let executionGate: EntitlementSourceExecutionGate

    var source: EntitlementSource {
        registration.source
    }

    var subject: EntitlementSubject {
        registration.subject
    }

    var freshnessPolicy: EntitlementFreshnessPolicy {
        registration.freshnessPolicy
    }

    var acceptanceGate: EntitlementSourceAcceptanceGate {
        registration.acceptanceGate
    }

    init(registration: EntitlementSourceRegistration) {
        self.registration = registration
        executionGate = EntitlementSourceExecutionGate(
            repository: registration.repository,
            subject: registration.subject
        )
    }
}

actor EntitlementSourceExecutionGate {
    private let repository: any EntitlementSourceRepositoryProtocol
    private let subject: EntitlementSubject
    private var generation: UInt64 = 0
    private var latestRefreshGeneration: UInt64 = 0
    private var inFlight: InFlight?
    private var acceptsNewWaiters = false
    private var waiters: [UUID: CheckedContinuation<EntitlementSourceResolution, Never>] = [:]

    init(
        repository: any EntitlementSourceRepositoryProtocol,
        subject: EntitlementSubject
    ) {
        self.repository = repository
        self.subject = subject
    }

    func resolve(
        waiterID: UUID,
        refreshGeneration: UInt64,
        forceNewGeneration: Bool
    ) async -> EntitlementSourceResolution {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(returning: .unresolved)
                    return
                }

                guard refreshGeneration >= latestRefreshGeneration else {
                    continuation.resume(returning: .unresolved)
                    return
                }

                if refreshGeneration > latestRefreshGeneration, forceNewGeneration {
                    supersedeSource()
                }
                latestRefreshGeneration = refreshGeneration

                guard inFlight == nil || acceptsNewWaiters else {
                    continuation.resume(returning: .unresolved)
                    return
                }

                waiters[waiterID] = continuation
                startSourceIfNeeded()
            }
        } onCancel: {
            Task {
                await self.cancelWaiter(waiterID)
            }
        }
    }

    private func supersedeSource() {
        guard let inFlight else {
            return
        }

        inFlight.task.cancel()
        self.inFlight = nil
        acceptsNewWaiters = false
        let continuations = Array(waiters.values)
        waiters.removeAll()
        for continuation in continuations {
            continuation.resume(returning: .unresolved)
        }
    }

    private func startSourceIfNeeded() {
        guard inFlight == nil else {
            return
        }

        generation &+= 1
        let currentGeneration = generation
        let repository = repository
        let subject = subject
        acceptsNewWaiters = true
        let task = Task {
            let resolution = await repository.resolveEntitlement(for: subject)
            complete(
                resolution,
                generation: currentGeneration
            )
        }
        inFlight = InFlight(
            generation: currentGeneration,
            task: task
        )
    }

    private func complete(
        _ resolution: EntitlementSourceResolution,
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
            continuation.resume(returning: resolution)
        }
    }

    func cancelWaiter(_ waiterID: UUID) {
        guard let continuation = waiters.removeValue(forKey: waiterID) else {
            return
        }

        continuation.resume(returning: .unresolved)
        if waiters.isEmpty {
            acceptsNewWaiters = false
        }
    }
}

private extension EntitlementSourceExecutionGate {
    struct InFlight {
        let generation: UInt64
        let task: Task<Void, Never>
    }
}
