import Foundation

@main
enum SpecialOfferCampaignProbe {
    private static let day: TimeInterval = 24 * 60 * 60
    private static let cadence = SpecialOfferCadence()
    private static let origin = Date(timeIntervalSinceReferenceDate: 800_000_000)

    static func main() {
        checkFirstOfferStartsNow()
        checkAskingInsideWindowDoesNotRestartIt()
        checkWindowEndIsExclusiveAndOpensCooldown()
        checkCooldownEndOpensANewWindow()
        checkDeviceClockMovedBackCannotExtendTheOffer()
        checkRemoteDurationsOverrideTheDefaults()
        checkRemainingTimeIsMeasuredAgainstServerTime()
        checkConfigurationDefaultsAreOneDayOnOneDayOff()
        print(
            "PASS: special-offer campaign cadence runs a day on and a day off, "
                + "cannot be restarted inside its window and cannot be extended "
                + "by moving the clock"
        )
    }

    private static func checkFirstOfferStartsNow() {
        guard case let .starts(window) = decision(startedAt: nil, at: 0) else {
            fatalError("A user with no stored window must be offered a fresh one")
        }
        guard window.startedAt == origin, window.expiresAt == origin.addingTimeInterval(day) else {
            fatalError("A fresh window must run one day from now")
        }
    }

    private static func checkAskingInsideWindowDoesNotRestartIt() {
        for elapsed in [1.0, day / 2, day - 1] {
            guard case let .live(window) = decision(startedAt: origin, at: elapsed) else {
                fatalError("The offer must stay live \(elapsed)s into its window")
            }
            guard window.startedAt == origin else {
                fatalError("Asking inside the window must not restart it")
            }
            let remaining = window.remainingTimeInterval(at: origin.addingTimeInterval(elapsed))
            guard remaining == day - elapsed else {
                fatalError("Remaining time at \(elapsed)s must be \(day - elapsed), got \(remaining)")
            }
        }
    }

    private static func checkWindowEndIsExclusiveAndOpensCooldown() {
        guard case let .cooldown(until) = decision(startedAt: origin, at: day) else {
            fatalError("The quiet period must begin the moment the window runs out")
        }
        guard until == origin.addingTimeInterval(2 * day) else {
            fatalError("The quiet period must end one day after the window did")
        }
        guard case .cooldown = decision(startedAt: origin, at: 2 * day - 1) else {
            fatalError("The offer must stay quiet until the last second of the cooldown")
        }
    }

    private static func checkCooldownEndOpensANewWindow() {
        let elapsed = 2 * day
        guard case let .starts(window) = decision(startedAt: origin, at: elapsed) else {
            fatalError("A new offer must be available once the quiet period is over")
        }
        guard window.startedAt == origin.addingTimeInterval(elapsed) else {
            fatalError("The new window must start now, not when the previous one did")
        }
    }

    private static func checkDeviceClockMovedBackCannotExtendTheOffer() {
        // Server time never moves backwards, but a stored start from a clock that
        // did must not read as an endless offer either.
        guard case let .live(window) = decision(startedAt: origin, at: -1000) else {
            fatalError("A reading before the window started must still see that window")
        }
        guard window.expiresAt == origin.addingTimeInterval(day) else {
            fatalError("Moving the clock back must not move the end of the window")
        }
        let remaining = window.remainingTimeInterval(at: origin.addingTimeInterval(-1000))
        guard remaining == day else {
            fatalError(
                "A reading before the window started must show a full window, not \(remaining)"
            )
        }
    }

    private static func checkRemoteDurationsOverrideTheDefaults() {
        let hour: TimeInterval = 3600
        guard case let .live(window) = cadence.decision(
            startedAt: origin,
            now: origin.addingTimeInterval(hour / 2),
            windowDuration: hour,
            cooldownDuration: 2 * hour
        ) else {
            fatalError("A one-hour campaign must be live half an hour in")
        }
        guard window.expiresAt == origin.addingTimeInterval(hour) else {
            fatalError("A dashboard duration must define the end of the window")
        }
        guard case let .cooldown(until) = cadence.decision(
            startedAt: origin,
            now: origin.addingTimeInterval(hour),
            windowDuration: hour,
            cooldownDuration: 2 * hour
        ), until == origin.addingTimeInterval(3 * hour) else {
            fatalError("A dashboard cooldown must define the end of the quiet period")
        }
    }

    private static func checkRemainingTimeIsMeasuredAgainstServerTime() {
        let window = SpecialOfferCampaignWindow(
            startedAt: origin,
            expiresAt: origin.addingTimeInterval(day)
        )
        let campaign = SpecialOfferCampaign(
            placementID: .specialOffer,
            variationID: nil,
            window: window,
            resolvedAt: origin.addingTimeInterval(day / 4)
        )
        guard campaign.remainingTimeInterval == day * 3 / 4 else {
            fatalError("A campaign must report the time left at the moment it was resolved")
        }
        guard window.remainingTimeInterval(at: origin.addingTimeInterval(2 * day)) == 0 else {
            fatalError("Remaining time must never go negative")
        }
    }

    private static func checkConfigurationDefaultsAreOneDayOnOneDayOff() {
        let configuration = SpecialOfferCampaignConfiguration(placementID: .specialOffer)
        guard configuration.windowDuration == day,
              configuration.cooldownDuration == day,
              configuration.gatePlacementID == .main,
              configuration.timePolicy == .requireServerTime
        else {
            fatalError(
                "The default campaign is a day on, a day off, and refuses to run "
                    + "without server time"
            )
        }
    }

    private static func decision(
        startedAt: Date?,
        at elapsed: TimeInterval
    ) -> SpecialOfferCadence.Decision {
        cadence.decision(
            startedAt: startedAt,
            now: origin.addingTimeInterval(elapsed),
            windowDuration: day,
            cooldownDuration: day
        )
    }
}
