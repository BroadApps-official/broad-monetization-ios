import BroadCore
import Foundation

/// Decides *when* a campaign is asked for, so a host does not have to.
///
/// The offer follows a paywall the user closed without buying: that is the whole
/// rule, and it is the platform's rule here rather than something every project
/// reimplements in its navigation. The coordinator reads the monetization event
/// it already emits — ``MonetizationAnalyticsEvent/paywallClosed(_:reason:)`` with
/// ``PaywallCloseReason/dismissed`` — resolves a campaign, and publishes the
/// decision on ``decisions``. A host subscribes once and renders what arrives.
///
/// It never follows itself: a close of one of the campaign's own placements is
/// ignored, so a dismissed offer cannot summon another one. A purchase or a
/// restore ends the campaign instead of following it, and an active subscription
/// is refused inside the resolver — so nothing shows to a paying user even if a
/// stale event arrives late.
///
/// Wire it either by feeding it every event with ``handle(_:)`` from an analytics
/// destination the project already owns, or by wrapping that destination in
/// ``SpecialOfferCampaignAnalyticsRelay``.
public actor SpecialOfferCampaignCoordinator {
    private let resolve: any SpecialOfferCampaignResolving
    private let campaignPlacementIDs: Set<PlacementID>
    private let followedPlacementIDs: Set<PlacementID>?
    private let continuation: AsyncStream<SpecialOfferCampaignOutcome>.Continuation

    /// Every decision this coordinator makes, newest first when a consumer falls
    /// behind. Refusals are published too, so a project can log why today had no
    /// offer without reaching into the platform.
    public nonisolated let decisions: AsyncStream<SpecialOfferCampaignOutcome>

    private var isResolving = false

    /// - Parameters:
    ///   - resolve: the campaign resolver. Its own placements are read from it,
    ///     so the screens the offer must not follow can never drift from the
    ///     screens it may open.
    ///   - followedPlacementIDs: which paywalls an offer follows. `nil` follows
    ///     every paywall except the campaign's own — right for an app with one
    ///     subscription screen. An app that also sells consumables should name
    ///     its subscription placements here, so closing a token pack does not
    ///     produce a subscription discount.
    public init(
        resolve: any SpecialOfferCampaignResolving,
        followedPlacementIDs: Set<PlacementID>? = nil
    ) {
        self.resolve = resolve
        campaignPlacementIDs = resolve.campaignPlacementIDs
        self.followedPlacementIDs = followedPlacementIDs

        let (stream, continuation) = AsyncStream<SpecialOfferCampaignOutcome>.makeStream(
            bufferingPolicy: .bufferingNewest(4)
        )
        decisions = stream
        self.continuation = continuation
    }

    /// Feed every monetization event here. Everything but a paywall close, a
    /// purchase and a restore is ignored.
    public func handle(_ event: MonetizationAnalyticsEvent) async {
        switch event {
        case let .paywallClosed(context, reason):
            await handlePaywallClose(context, reason: reason)
        case .purchaseSuccess, .restoreSuccess:
            // The campaign is over for this user. The next one starts from
            // scratch rather than resuming a quiet period nobody is waiting on.
            await resolve.purchaseDidConfirm()
        default:
            break
        }
    }

    /// Asks for a campaign now and publishes the decision, for a host that wants
    /// its own trigger in addition to following a paywall.
    ///
    /// Returns `nil` when a resolution is already running: asking twice would
    /// hand one provider presentation to two screens, and the answer is already
    /// on its way to ``decisions``.
    @discardableResult
    public func resolveNow() async -> SpecialOfferCampaignOutcome? {
        guard !isResolving else {
            return nil
        }

        isResolving = true
        let outcome = await resolve()
        isResolving = false
        continuation.yield(outcome)
        return outcome
    }

    /// Ends the decision stream. A composition that outlives the app does not
    /// need this; it exists so a torn-down feature does not leave a consumer
    /// awaiting forever.
    public func finish() {
        continuation.finish()
    }

    private func handlePaywallClose(
        _ context: PaywallAnalyticsContext,
        reason: PaywallCloseReason
    ) async {
        switch reason {
        case .purchased:
            await resolve.purchaseDidConfirm()
        case .dismissed:
            guard shouldFollow(context) else {
                return
            }
            await resolveNow()
        case .unavailable, .navigation:
            // Nothing was refused by the user: the paywall could not be shown, or
            // the app moved on by itself. Following either with a discount would
            // put an offer in front of a user who never saw the price.
            break
        }
    }

    private func shouldFollow(_ context: PaywallAnalyticsContext) -> Bool {
        // Never follow the campaign's own screen: a dismissed offer must not
        // summon the next one.
        guard !campaignPlacementIDs.contains(context.requestedPlacementID),
              !campaignPlacementIDs.contains(context.resolvedPlacementID)
        else {
            return false
        }
        guard let followedPlacementIDs else {
            return true
        }
        return followedPlacementIDs.contains(context.requestedPlacementID)
    }
}
