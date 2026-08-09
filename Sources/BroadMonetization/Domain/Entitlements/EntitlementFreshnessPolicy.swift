import Foundation

public struct EntitlementFreshnessPolicy: Equatable, Sendable {
    public let timeToLive: TimeInterval
    public let offlineActiveGrace: TimeInterval

    public init(
        timeToLive: TimeInterval,
        offlineActiveGrace: TimeInterval
    ) {
        precondition(
            timeToLive.isFinite && timeToLive > 0,
            "Entitlement timeToLive must be finite and greater than zero"
        )
        precondition(
            offlineActiveGrace.isFinite && offlineActiveGrace >= 0,
            "Entitlement offline grace must be finite and non-negative"
        )

        self.timeToLive = timeToLive
        self.offlineActiveGrace = offlineActiveGrace
    }
}
