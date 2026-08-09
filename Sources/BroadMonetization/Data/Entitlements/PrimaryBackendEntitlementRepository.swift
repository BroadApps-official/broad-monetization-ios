import BroadCore

public struct PrimaryBackendEntitlementRepository: EntitlementSourceRepositoryProtocol {
    private let client: any PrimaryBackendEntitlementClientProtocol
    private let clock: CacheClock

    public init(
        client: any PrimaryBackendEntitlementClientProtocol,
        clock: CacheClock = .system
    ) {
        self.client = client
        self.clock = clock
    }

    public func resolveEntitlement(
        for subject: EntitlementSubject
    ) async -> EntitlementSourceResolution {
        guard !Task.isCancelled else {
            return .unresolved
        }

        let result = await client.loadEntitlement(for: subject)

        guard !Task.isCancelled else {
            return .unresolved
        }

        guard case let .serverValidated(snapshot) = result,
              snapshot.subject == subject
        else {
            return .unresolved
        }

        guard snapshot.isActive else {
            guard !snapshot.isLifetime else {
                return .unresolved
            }
            guard let expirationDate = snapshot.expiresAt else {
                return .inactive
            }
            guard expirationDate.timeIntervalSinceReferenceDate.isFinite else {
                return .unresolved
            }
            return expirationDate <= clock.now() ? .inactive : .unresolved
        }

        if snapshot.isLifetime {
            return snapshot.expiresAt == nil ? .active(.lifetime) : .unresolved
        }

        guard let expirationDate = snapshot.expiresAt else {
            return .active(.unspecified)
        }

        guard expirationDate.timeIntervalSinceReferenceDate.isFinite,
              expirationDate > clock.now()
        else {
            return .unresolved
        }

        return .active(.expires(at: expirationDate))
    }
}
