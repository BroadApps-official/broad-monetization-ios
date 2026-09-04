import Foundation

/// What to do when the current time cannot be proven against the host's backend.
///
/// A window measured on the device clock is a window the user can extend: move the
/// date back and the offer never ends, move it forward and the quiet period is
/// over. The default therefore refuses to run at all rather than run on a clock
/// the platform cannot vouch for.
public enum SpecialOfferCampaignTimePolicy: String, Codable, Equatable, Sendable {
    /// No campaign until a server date has been recorded. The default.
    case requireServerTime = "require-server-time"

    /// Run on the device clock while server time is missing. A deliberate choice
    /// a project has to write down; it accepts that the window is movable.
    case allowDeviceClock = "allow-device-clock"
}

/// Host-owned configuration of the campaign track.
///
/// Placements are tried in order, so a dashboard that carries the same campaign
/// under two names (`special_offer` and a plain `offer`, say) needs no extra host
/// code. Durations are the fallback for a dashboard that says nothing: a campaign
/// payload that carries its own duration or cooldown overrides them.
public struct SpecialOfferCampaignConfiguration: Equatable, Sendable {
    /// One day of offer, then one quiet day. The cadence every BroadApps project
    /// has shipped so far, kept as the default so nobody has to restate it.
    public static let defaultWindowDuration: TimeInterval = 24 * 60 * 60
    public static let defaultCooldownDuration: TimeInterval = 24 * 60 * 60

    public let placementIDs: [PlacementID]
    public let windowDuration: TimeInterval
    public let cooldownDuration: TimeInterval
    public let timePolicy: SpecialOfferCampaignTimePolicy

    public init(
        placementIDs: [PlacementID],
        windowDuration: TimeInterval = Self.defaultWindowDuration,
        cooldownDuration: TimeInterval = Self.defaultCooldownDuration,
        timePolicy: SpecialOfferCampaignTimePolicy = .requireServerTime
    ) {
        precondition(
            !placementIDs.isEmpty,
            "A special-offer campaign requires at least one placement"
        )
        precondition(
            Set(placementIDs).count == placementIDs.count,
            "Special-offer campaign placements must be unique"
        )
        precondition(
            SpecialOfferDurationPolicy.isValid(windowDuration),
            "Special-offer window duration must be finite, positive and within the supported limit"
        )
        precondition(
            SpecialOfferDurationPolicy.isValid(cooldownDuration),
            "Special-offer cooldown duration must be finite, positive and within the supported limit"
        )

        self.placementIDs = placementIDs
        self.windowDuration = windowDuration
        self.cooldownDuration = cooldownDuration
        self.timePolicy = timePolicy
    }

    public init(
        placementID: PlacementID,
        windowDuration: TimeInterval = Self.defaultWindowDuration,
        cooldownDuration: TimeInterval = Self.defaultCooldownDuration,
        timePolicy: SpecialOfferCampaignTimePolicy = .requireServerTime
    ) {
        self.init(
            placementIDs: [placementID],
            windowDuration: windowDuration,
            cooldownDuration: cooldownDuration,
            timePolicy: timePolicy
        )
    }
}

/// The stretch of server time during which the current offer may be shown.
public struct SpecialOfferCampaignWindow: Equatable, Sendable {
    public let startedAt: Date
    public let expiresAt: Date

    public init(
        startedAt: Date,
        expiresAt: Date
    ) {
        precondition(
            startedAt.timeIntervalSinceReferenceDate.isFinite
                && expiresAt.timeIntervalSinceReferenceDate.isFinite
                && expiresAt > startedAt,
            "A special-offer window requires finite, ordered dates"
        )
        self.startedAt = startedAt
        self.expiresAt = expiresAt
    }

    /// Never more than the window is long and never less than zero. A server
    /// correction may report a moment before this window opened; that must read
    /// as a full window, not as more than one.
    public func remainingTimeInterval(at date: Date) -> TimeInterval {
        max(0, expiresAt.timeIntervalSince(max(date, startedAt)))
    }
}

/// Why a placement did not become an offer. Returned rather than logged, so the
/// host can tell "no campaign today" from "the campaign is broken" with its own
/// logger and without a debugger.
public enum SpecialOfferCampaignRefusal: String, Codable, Equatable, Sendable {
    /// The subscription is already active. No paywall, cache or network work is
    /// performed for a user who has nothing to buy.
    case alreadyEntitled = "already-entitled"

    /// No server date has been recorded and the policy requires one.
    case serverTimeUnavailable = "server-time-unavailable"

    /// The placement did not answer with a paywall at all.
    case placementUnavailable = "placement-unavailable"

    /// The provider answered with another placement's paywall. Showing that
    /// substitute under a discount would be an invented offer.
    case substitutedPaywall = "substituted-paywall"

    /// The payload was restored from the platform's own cache, which proves
    /// nothing about a campaign still running.
    case stalePayload = "stale-payload"

    /// The dashboard kill switch is explicitly off. An absent flag is neutral.
    case disabledRemotely = "disabled-remotely"

    /// The campaign carries nothing to buy.
    case emptyCatalog = "empty-catalog"

    /// The quiet period after the previous offer has not elapsed.
    case cooldown

    /// The window could not be written, so the offer would not be remembered.
    case persistenceUnavailable = "persistence-unavailable"
}

/// A campaign that may be presented now.
///
/// Carries the placement rather than a payload: the screen loads that placement
/// for itself, which keeps the presentation it renders under its own ownership.
/// The resolver closes the presentation it used to make this decision.
public struct SpecialOfferCampaign: Equatable, Sendable {
    public let placementID: PlacementID
    public let variationID: PaywallVariationID?
    public let window: SpecialOfferCampaignWindow

    /// Server time when the decision was made. The countdown a screen shows is
    /// `remainingTimeInterval` counted off a monotonic timer from here — the one
    /// thing the user cannot move.
    public let resolvedAt: Date

    public init(
        placementID: PlacementID,
        variationID: PaywallVariationID?,
        window: SpecialOfferCampaignWindow,
        resolvedAt: Date
    ) {
        self.placementID = placementID
        self.variationID = variationID
        self.window = window
        self.resolvedAt = resolvedAt
    }

    public var remainingTimeInterval: TimeInterval {
        window.remainingTimeInterval(at: resolvedAt)
    }
}

public enum SpecialOfferCampaignOutcome: Equatable, Sendable {
    case campaign(SpecialOfferCampaign)
    case unavailable(SpecialOfferCampaignRefusal)

    public var campaign: SpecialOfferCampaign? {
        switch self {
        case let .campaign(campaign):
            campaign
        case .unavailable:
            nil
        }
    }
}
