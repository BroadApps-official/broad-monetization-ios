import Foundation

/// Authorization for the special-offer countdown.
///
/// Two modes:
/// - **Windowed** (`init(window:trustedTime:)`): a real campaign window drives a
///   monotonic countdown that reaches zero and reports `isExpired`. The remaining
///   time is captured against the trusted reading's monotonic anchor, so async
///   work and device-clock changes cannot stretch it.
/// - **Looping** (`init()`): the legacy display-only counter that repeats
///   `24:00:00 -> 00:00:00 -> 24:00:00` forever and never expires. Used for untimed
///   offers that do not run the cadence engine.
public struct SpecialOfferCountdownAuthorization: Equatable, Sendable {
    public static let cycleDuration: TimeInterval = 24 * 60 * 60

    private static let cycleFrameCount = Int(cycleDuration) + 1

    private enum Mode: Equatable, Sendable {
        /// Legacy visual loop anchored to a monotonic start instant.
        case looping(startedAt: ContinuousClock.Instant)
        /// Real window: seconds remaining captured against a monotonic anchor.
        case windowed(remaining: TimeInterval, anchor: ContinuousClock.Instant)
    }

    private let mode: Mode

    init(startedAt: ContinuousClock.Instant = ContinuousClock().now) {
        mode = .looping(startedAt: startedAt)
    }

    /// A countdown bounded by a real campaign window. The remaining time is
    /// `window.expiresAt - trustedTime.date`, clamped to zero, counted off the
    /// monotonic instant at which the trusted time was observed.
    init(
        window: SpecialOfferWindow,
        trustedTime: SpecialOfferTrustedTime
    ) {
        let remaining = max(0, window.expiresAt.timeIntervalSince(trustedTime.date))
        mode = .windowed(remaining: remaining, anchor: trustedTime.observedAt)
    }

    public var remainingTimeInterval: TimeInterval {
        switch mode {
        case let .looping(startedAt):
            let elapsed = Self.timeInterval(
                from: startedAt.duration(to: ContinuousClock().now)
            )
            return Self.remainingTimeInterval(elapsed: elapsed)
        case let .windowed(remaining, anchor):
            let elapsed = Self.timeInterval(
                from: anchor.duration(to: ContinuousClock().now)
            )
            return max(0, remaining - max(0, elapsed))
        }
    }

    /// Deterministic formatter input for the legacy looping counter. The extra
    /// frame lets the user see `00:00:00` before the next 24-hour loop.
    public static func remainingTimeInterval(
        elapsed: TimeInterval
    ) -> TimeInterval {
        guard elapsed.isFinite, elapsed > 0 else {
            return cycleDuration
        }

        let wholeSeconds = Int(elapsed.rounded(.down))
        let cyclePosition = wholeSeconds % cycleFrameCount
        return TimeInterval(Int(cycleDuration) - cyclePosition)
    }

    /// Whether a windowed countdown has reached zero. The legacy looping counter
    /// never expires.
    public var isExpired: Bool {
        switch mode {
        case .looping:
            false
        case .windowed:
            remainingTimeInterval <= 0
        }
    }

    /// Waits until the countdown reaches zero. For a windowed countdown this is a
    /// real expiration; for the legacy loop it is the next zero frame, which does
    /// not hide the offer.
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
