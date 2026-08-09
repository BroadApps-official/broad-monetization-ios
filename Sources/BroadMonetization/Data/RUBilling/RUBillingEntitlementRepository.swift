import BroadCore
import Foundation

public struct RUBillingEntitlementRepository: EntitlementSourceRepositoryProtocol {
    private let clients: [any RUBillingEntitlementClientProtocol]
    private let authorizationBinding: SubjectAuthorizationBinding
    private let clock: CacheClock

    public init(
        clients: [any RUBillingEntitlementClientProtocol],
        authorizationBinding: SubjectAuthorizationBinding,
        clock: CacheClock = .system
    ) {
        precondition(
            !clients.isEmpty,
            "RU billing entitlement repository needs at least one authoritative client"
        )
        self.clients = clients
        self.authorizationBinding = authorizationBinding
        self.clock = clock
    }

    public func resolveEntitlement(
        for subject: EntitlementSubject
    ) async -> EntitlementSourceResolution {
        guard authorizationBinding.subject == subject,
              authorizationBinding.isCurrent()
        else {
            return .unresolved
        }
        let operation = RUBillingEntitlementOperation(
            clients: clients,
            subject: subject,
            authorizationBinding: authorizationBinding,
            clock: clock
        )
        return await operation.resolve()
    }
}

private actor RUBillingEntitlementOperation {
    private let clients: [any RUBillingEntitlementClientProtocol]
    private let subject: EntitlementSubject
    private let authorizationBinding: SubjectAuthorizationBinding
    private let clock: CacheClock

    private var tasks: [Task<Void, Never>] = []
    private var continuation: CheckedContinuation<EntitlementSourceResolution, Never>?
    private var completedResolutions: [EntitlementSourceResolution] = []
    private var isFinished = false

    init(
        clients: [any RUBillingEntitlementClientProtocol],
        subject: EntitlementSubject,
        authorizationBinding: SubjectAuthorizationBinding,
        clock: CacheClock
    ) {
        self.clients = clients
        self.subject = subject
        self.authorizationBinding = authorizationBinding
        self.clock = clock
    }

    func resolve() async -> EntitlementSourceResolution {
        await withTaskCancellationHandler {
            guard authorizationBinding.isCurrent(),
                  !Task.isCancelled
            else {
                return .unresolved
            }

            let resolution = await withCheckedContinuation { continuation in
                self.continuation = continuation
                startClients()
            }
            return Task.isCancelled || !authorizationBinding.isCurrent()
                ? .unresolved
                : resolution
        } onCancel: {
            Task {
                await self.cancel()
            }
        }
    }

    private func startClients() {
        for client in clients {
            let task = Task {
                let result = await client.loadEntitlement(for: subject)
                guard authorizationBinding.isCurrent() else {
                    accept(.unresolved)
                    return
                }
                accept(
                    Self.resolve(
                        result,
                        subject: subject,
                        now: clock.now()
                    )
                )
            }
            tasks.append(task)
        }
    }

    private func accept(_ resolution: EntitlementSourceResolution) {
        guard !isFinished else {
            return
        }
        guard authorizationBinding.isCurrent() else {
            finish(with: .unresolved)
            return
        }
        completedResolutions.append(resolution)

        if case .active = resolution {
            finish(with: aggregateActiveResolution())
            return
        }

        guard completedResolutions.count == clients.count else {
            return
        }
        finish(
            with: completedResolutions.allSatisfy { $0 == .inactive }
                ? .inactive
                : .unresolved
        )
    }

    private func aggregateActiveResolution() -> EntitlementSourceResolution {
        let validities = completedResolutions.compactMap { resolution -> EntitlementActiveValidity? in
            guard case let .active(validity) = resolution else {
                return nil
            }
            return validity
        }
        if validities.contains(.lifetime) {
            return .active(.lifetime)
        }
        if validities.contains(.unspecified) {
            return .active(.unspecified)
        }
        return .active(
            validities.compactMap(\.expirationDate).max().map {
                .expires(at: $0)
            } ?? .unspecified
        )
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

    static func resolve(
        _ result: RUBillingEntitlementClientResult,
        subject: EntitlementSubject,
        now: Date
    ) -> EntitlementSourceResolution {
        guard case let .serverValidated(record) = result,
              record.subject == subject,
              now.timeIntervalSinceReferenceDate.isFinite,
              record.expiresAt?.timeIntervalSinceReferenceDate.isFinite != false
        else {
            return .unresolved
        }

        if record.isActive {
            if record.isLifetime {
                return record.expiresAt == nil ? .active(.lifetime) : .unresolved
            }
            guard let expiresAt = record.expiresAt else {
                return .active(.unspecified)
            }
            return expiresAt > now ? .active(.expires(at: expiresAt)) : .unresolved
        }

        guard !record.isLifetime,
              record.expiresAt.map({ $0 <= now }) ?? true
        else {
            return .unresolved
        }
        return .inactive
    }
}
