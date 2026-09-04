import Foundation

/// Authorization for a countdown bounded by the current 24-hour offer window.
/// It reaches zero once, expires and never starts another visual loop.
public struct SpecialOfferCountdownAuthorization: Equatable, Sendable {
    public static let cycleDuration = SpecialOfferConfiguration.standardWindowDuration

    private let initialRemainingTime: TimeInterval
    private let anchor: ContinuousClock.Instant

    init(
        window: SpecialOfferWindow,
        trustedTime: SpecialOfferTrustedTime
    ) {
        let windowDuration = window.expiresAt.timeIntervalSince(window.startedAt)
        initialRemainingTime = min(
            windowDuration,
            max(0, window.expiresAt.timeIntervalSince(trustedTime.date))
        )
        anchor = trustedTime.observedAt
    }

    public var remainingTimeInterval: TimeInterval {
        let elapsed = Self.timeInterval(
            from: anchor.duration(to: ContinuousClock().now)
        )
        return Self.remainingTimeInterval(
            initialRemainingTime: initialRemainingTime,
            elapsed: elapsed
        )
    }

    /// Source-compatible deterministic helper for a full standard window.
    /// Unlike the former visual loop, values after 24 hours remain at zero.
    public static func remainingTimeInterval(
        elapsed: TimeInterval
    ) -> TimeInterval {
        remainingTimeInterval(
            initialRemainingTime: cycleDuration,
            elapsed: elapsed
        )
    }

    public static func remainingTimeInterval(
        initialRemainingTime: TimeInterval,
        elapsed: TimeInterval
    ) -> TimeInterval {
        guard initialRemainingTime.isFinite,
              initialRemainingTime > 0,
              elapsed.isFinite
        else {
            return 0
        }
        return max(0, initialRemainingTime - max(0, elapsed))
    }

    public var isExpired: Bool {
        remainingTimeInterval <= 0
    }

    public func sleepUntilExpiration() async throws {
        try await ContinuousClock().sleep(
            for: .seconds(max(remainingTimeInterval, 0))
        )
    }

    private static func timeInterval(
        from duration: Duration
    ) -> TimeInterval {
        let components = duration.components
        return Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
