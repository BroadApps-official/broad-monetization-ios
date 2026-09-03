import Foundation

/// The rule behind "a day of offer, then a quiet day", as arithmetic on its own.
///
/// Kept apart from where the timestamp is stored so the decision can be examined
/// directly: given when the current offer started and what time it is now, may an
/// offer be shown, and until when. Storage adds nothing to it but the read and
/// the write.
///
/// Both boundaries are derived rather than stored. Nothing about the expired
/// state is kept, so a duration changed in the dashboard takes effect for the
/// running window too instead of being frozen at whatever was current when it
/// opened.
public struct SpecialOfferCadence: Equatable, Sendable {
    public enum Decision: Equatable, Sendable {
        /// The window already running.
        case live(SpecialOfferCampaignWindow)

        /// No window is running and one may start now. The caller is expected to
        /// persist `startedAt` before showing anything: an offer nobody
        /// remembers would start again on the very next paywall.
        case starts(SpecialOfferCampaignWindow)

        /// The previous window has ended and the quiet period has not elapsed.
        case cooldown(until: Date)
    }

    public init() {}

    public func decision(
        startedAt: Date?,
        now: Date,
        windowDuration: TimeInterval,
        cooldownDuration: TimeInterval
    ) -> Decision {
        precondition(
            SpecialOfferDurationPolicy.isValid(windowDuration)
                && SpecialOfferDurationPolicy.isValid(cooldownDuration),
            "Special-offer durations must be finite, positive and within the supported limit"
        )

        if let startedAt, startedAt.timeIntervalSinceReferenceDate.isFinite {
            let expiresAt = startedAt.addingTimeInterval(windowDuration)
            if now < expiresAt {
                // A window that has not run out is returned as it is: asking
                // again inside it must not extend it or start a second one.
                return .live(
                    SpecialOfferCampaignWindow(startedAt: startedAt, expiresAt: expiresAt)
                )
            }

            let quietUntil = expiresAt.addingTimeInterval(cooldownDuration)
            if now < quietUntil {
                return .cooldown(until: quietUntil)
            }
        }

        return .starts(
            SpecialOfferCampaignWindow(
                startedAt: now,
                expiresAt: now.addingTimeInterval(windowDuration)
            )
        )
    }
}
