import BroadCore
import Foundation

public struct AdaptyAppleEntitlementConfiguration: Sendable {
    public let subject: EntitlementSubject
    public let accessLevelIdentifier: String

    public init(
        subject: EntitlementSubject,
        accessLevelIdentifier: String
    ) {
        let trimmedIdentifier = accessLevelIdentifier.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        precondition(
            !trimmedIdentifier.isEmpty && trimmedIdentifier == accessLevelIdentifier,
            "Adapty access level identifier must be nonempty and contain no surrounding whitespace"
        )

        self.subject = subject
        self.accessLevelIdentifier = accessLevelIdentifier
    }
}

public struct AdaptyAppleEntitlementVerifier: AppleEntitlementVerifierProtocol {
    private let configuration: AdaptyAppleEntitlementConfiguration
    private let client: any AdaptyEntitlementProfileClientProtocol
    private let clock: CacheClock

    public init(
        configuration: AdaptyAppleEntitlementConfiguration,
        client: any AdaptyEntitlementProfileClientProtocol,
        clock: CacheClock = .system
    ) {
        self.configuration = configuration
        self.client = client
        self.clock = clock
    }

    public func verifyEntitlement(
        for subject: EntitlementSubject
    ) async -> EntitlementSourceResolution {
        guard subject == configuration.subject, !Task.isCancelled else {
            return .unresolved
        }

        let result = await client.loadProfile(for: subject)

        guard !Task.isCancelled else {
            return .unresolved
        }

        guard case let .serverValidated(profile) = result else {
            return .unresolved
        }
        guard profile.subject == subject else {
            return .unresolved
        }
        guard
            let accessLevel = profile.accessLevels[configuration.accessLevelIdentifier]
        else {
            return .inactive
        }
        guard accessLevel.identifier == configuration.accessLevelIdentifier else {
            return .unresolved
        }
        guard accessLevel.isActive else {
            return .inactive
        }

        return activeResolution(accessLevel, now: clock.now())
    }
}

private extension AdaptyAppleEntitlementVerifier {
    func activeResolution(
        _ accessLevel: AdaptyEntitlementAccessLevelSnapshot,
        now: Date
    ) -> EntitlementSourceResolution {
        guard !accessLevel.isRefund else {
            return .unresolved
        }
        if let startsAt = accessLevel.startsAt {
            guard
                startsAt.timeIntervalSinceReferenceDate.isFinite,
                startsAt <= now
            else {
                return .unresolved
            }
        }

        if accessLevel.isLifetime {
            return accessLevel.expiresAt == nil
                ? .active(.lifetime)
                : .unresolved
        }

        guard let expiresAt = accessLevel.expiresAt else {
            return .active(.unspecified)
        }
        guard expiresAt.timeIntervalSinceReferenceDate.isFinite else {
            return .unresolved
        }
        if expiresAt > now {
            return .active(.expires(at: expiresAt))
        }

        return accessLevel.isInGracePeriod
            ? .active(.unspecified)
            : .unresolved
    }
}
