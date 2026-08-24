import Foundation

/// Authorization for a visual countdown only. It is intentionally independent
/// from campaign eligibility and repeats forever while the offer is visible:
/// `24:00:00 → 00:00:00 → 24:00:00`.
public struct SpecialOfferCountdownAuthorization: Equatable, Sendable {
    public static let cycleDuration: TimeInterval = 24 * 60 * 60

    private static let cycleFrameCount = Int(cycleDuration) + 1
    private let startedAt: ContinuousClock.Instant

    init(startedAt: ContinuousClock.Instant = ContinuousClock().now) {
        self.startedAt = startedAt
    }

    public var remainingTimeInterval: TimeInterval {
        let elapsed = Self.timeInterval(
            from: startedAt.duration(to: ContinuousClock().now)
        )
        return Self.remainingTimeInterval(elapsed: elapsed)
    }

    /// Deterministic formatter input used by the runtime contract probe and UI.
    /// The extra frame lets the user see `00:00:00` before the next 24-hour loop.
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

    /// Compatibility value for integrations that used to stop purchases when a
    /// real campaign window expired. The visual countdown never expires.
    @available(*, deprecated, message: "The Special Offer display countdown never expires")
    public var isExpired: Bool {
        false
    }

    /// Compatibility helper: waits until the visual counter reaches its next
    /// zero frame. Reaching zero does not invalidate or hide the offer.
    @available(*, deprecated, message: "Wait for UI refreshes; Special Offer never expires")
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
