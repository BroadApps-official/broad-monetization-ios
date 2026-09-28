import Foundation

extension ResolveSpecialOfferUseCase {
    /// The cadence is continuous after the first qualifying close: every
    /// 24-hour active phase is followed immediately by a 24-hour cooldown, even
    /// while the app is not running.
    static func nextState(
        from state: SpecialOfferState,
        now: Date
    ) -> SpecialOfferState {
        switch state {
        case let .active(window):
            return phase(
                startingAt: window.startedAt,
                now: now
            )
        case let .cooldown(until):
            if now < until {
                return .cooldown(until: until)
            }
            return phase(startingAt: until, now: now)
        case .eligible, .expired, .unavailable:
            return .active(newWindow(startingAt: now))
        }
    }

    static func phase(
        startingAt initialWindowStart: Date,
        now: Date
    ) -> SpecialOfferState {
        let windowDuration = defaultWindowDuration
        let cooldownDuration = defaultCooldownDuration
        let fullCycleDuration = windowDuration + cooldownDuration
        let elapsed = max(0, now.timeIntervalSince(initialWindowStart))
        let completedCycles = floor(elapsed / fullCycleDuration)
        let cycleStart = initialWindowStart.addingTimeInterval(
            completedCycles * fullCycleDuration
        )
        let activeUntil = cycleStart.addingTimeInterval(windowDuration)
        if now < activeUntil {
            return .active(
                SpecialOfferWindow(startedAt: cycleStart, expiresAt: activeUntil)
            )
        }
        return .cooldown(
            until: cycleStart.addingTimeInterval(fullCycleDuration)
        )
    }

    static func newWindow(
        startingAt date: Date
    ) -> SpecialOfferWindow {
        SpecialOfferWindow(
            startedAt: date,
            expiresAt: date.addingTimeInterval(defaultWindowDuration)
        )
    }
}
