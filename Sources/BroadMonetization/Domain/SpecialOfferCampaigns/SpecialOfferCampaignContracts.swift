import Foundation

/// What the stored window says about showing an offer right now.
public enum SpecialOfferCampaignWindowDecision: Equatable, Sendable {
    /// A window is running, either the one already open or a fresh one that
    /// started with this very question.
    case open(SpecialOfferCampaignWindow)

    /// The previous window has ended and the quiet period has not elapsed.
    case cooldown(until: Date)

    /// The window could not be persisted. Treated as a refusal, because an offer
    /// nobody remembers would start again on the next paywall.
    case unwritable
}

/// Remembers when the current offer started, so a relaunch two hours in still
/// sees two hours.
///
/// Asking is what opens a window: a live one is returned, a quiet period answers
/// `cooldown`, and otherwise a fresh window starts from `now`. That keeps the
/// cadence honest — the offer is spent when it is shown, not when it is resolved
/// somewhere in the background.
public protocol SpecialOfferWindowStoreProtocol: Sendable {
    func windowForPresentation(
        now: Date,
        windowDuration: TimeInterval,
        cooldownDuration: TimeInterval
    ) async -> SpecialOfferCampaignWindowDecision

    /// Forgets the current window. A confirmed purchase ends the campaign, so the
    /// next one starts from scratch instead of resuming a quiet period nobody is
    /// waiting on.
    func clear() async
}

public protocol SpecialOfferCampaignResolving: Sendable {
    /// The placements this resolver may answer with. Whoever decides *when* to
    /// ask reads them from here rather than being handed a second copy of the
    /// configuration: two copies can drift, and a drifted copy means the offer
    /// stops recognizing its own screen and starts following itself.
    nonisolated var campaignPlacementIDs: Set<PlacementID> { get }

    func callAsFunction() async -> SpecialOfferCampaignOutcome
    func purchaseDidConfirm() async
}
