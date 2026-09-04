import BroadCore
import Foundation

/// Decides whether a discounted campaign may be shown right now, from the fact
/// that a campaign exists rather than from a flag beside it.
///
/// The campaign is the paywall of its own placement: when the provider answers
/// that placement with a paywall of its own and something to sell in it, there is
/// a campaign. A substituted, cache-restored, empty or explicitly disabled answer
/// is not. Nothing has to be added to a dashboard beyond the campaign itself,
/// which is what the flag-driven ``ResolveSpecialOfferUseCase`` requires and what
/// live campaigns in the field turned out not to carry.
///
/// This is a second, parallel path. ``ResolveSpecialOfferUseCase`` is unchanged
/// and still the right choice for a project whose dashboard does set
/// `special_offer`; a composition picks one of the two and nothing above it moves.
///
/// How often an offer may be shown is the platform's rule here, not the host's:
/// a day of offer, then a quiet day, measured on server time
/// (``ServerTimeProviderProtocol``) so the cadence cannot be moved with the
/// device clock. An active subscription is refused before any paywall, cache or
/// network work happens, so a paying user never even asks for a discount.
public actor ResolveSpecialOfferCampaignUseCase: SpecialOfferCampaignResolving {
    private let configuration: SpecialOfferCampaignConfiguration
    private let loadPaywallUseCase: any LoadPaywallUseCaseProtocol
    private let windowRepository: any SpecialOfferWindowStoreProtocol
    private let presentationLifecycle: any PaywallPresentationLifecycleProtocol
    private let entitlementStatusProvider: any EntitlementStatusProviderProtocol

    /// Deliberately without a default value. A host that forgets to pass trusted
    /// time does not compile, instead of shipping a window the user can move.
    private let serverTime: any ServerTimeProviderProtocol

    public init(
        configuration: SpecialOfferCampaignConfiguration,
        loadPaywallUseCase: any LoadPaywallUseCaseProtocol,
        windowRepository: any SpecialOfferWindowStoreProtocol,
        presentationLifecycle: any PaywallPresentationLifecycleProtocol,
        entitlementStatusProvider: any EntitlementStatusProviderProtocol,
        serverTime: any ServerTimeProviderProtocol
    ) {
        self.configuration = configuration
        self.loadPaywallUseCase = loadPaywallUseCase
        self.windowRepository = windowRepository
        self.presentationLifecycle = presentationLifecycle
        self.entitlementStatusProvider = entitlementStatusProvider
        self.serverTime = serverTime
    }

    public nonisolated var campaignPlacementIDs: Set<PlacementID> {
        Set(configuration.placementIDs)
    }

    public func callAsFunction() async -> SpecialOfferCampaignOutcome {
        // First and cheapest: a subscriber has nothing to buy at a discount. This
        // guard precedes every dependency access, so a paid user performs no
        // paywall, cache or network work at all.
        guard await entitlementStatusProvider.currentStatus() != .active else {
            return .unavailable(.alreadyEntitled)
        }

        let reading = await serverTime.reading()
        guard let now = authorizedTime(from: reading) else {
            return .unavailable(.serverTimeUnavailable)
        }

        var lastRefusal = SpecialOfferCampaignRefusal.placementUnavailable
        for placementID in configuration.placementIDs {
            switch await resolve(placementID: placementID, now: now) {
            case let .campaign(campaign):
                return .campaign(campaign)
            case let .unavailable(refusal):
                // A quiet period is a decision about the app, not about this one
                // placement: trying the next name would open a window the
                // cadence has already refused.
                guard refusal != .cooldown, refusal != .persistenceUnavailable else {
                    return .unavailable(refusal)
                }
                lastRefusal = refusal
            }
        }
        return .unavailable(lastRefusal)
    }

    public func purchaseDidConfirm() async {
        await windowRepository.clear()
    }
}

private extension ResolveSpecialOfferCampaignUseCase {
    func authorizedTime(from reading: ServerTimeReading) -> Date? {
        switch configuration.timePolicy {
        case .requireServerTime:
            reading.isSynchronized ? reading.date : nil
        case .allowDeviceClock:
            reading.date
        }
    }

    func resolve(
        placementID: PlacementID,
        now: Date
    ) async -> SpecialOfferCampaignOutcome {
        let outcome = await loadPaywallUseCase(PaywallLoadRequest(placementID: placementID))
        guard case let .loaded(paywall) = outcome else {
            return .unavailable(.placementUnavailable)
        }

        // The provider may answer a placement it does not have with the main
        // paywall. That substitute is the ordinary subscription screen, and
        // showing it as a discount would be an invented offer. Its remote
        // configuration belongs to main too, so reading a flag out of it would
        // mean deciding this campaign by another paywall's settings.
        guard !paywall.origin.usedFallback,
              paywall.origin.resolvedPlacementID == placementID
        else {
            return await refuse(.substitutedPaywall, endingPresentationOf: paywall)
        }

        // A payload the platform restored from its own cache proves nothing about
        // the campaign still running. Offline the offer stays away, which is also
        // the only honest answer: the products it sells would be stale too.
        guard paywall.remoteConfigurationProvenance.authorizesSpecialOfferPresentation else {
            return await refuse(.stalePayload, endingPresentationOf: paywall)
        }

        let remote = paywall.remoteConfiguration.specialOffer

        // The dashboard kill switch, for a dashboard that uses one: an explicit
        // `false` stops the campaign without a release. Absence means nothing
        // either way — this path is gated by the campaign, not by a flag.
        guard remote?.isEnabled != false else {
            return await refuse(.disabledRemotely, endingPresentationOf: paywall)
        }

        // An empty campaign must not spend the day: the window would open on a
        // screen with nothing on it, and the quiet day that follows would hide
        // the real offer once the placement is filled in.
        guard !paywall.products.isEmpty else {
            return await refuse(.emptyCatalog, endingPresentationOf: paywall)
        }

        let decision = await windowRepository.windowForPresentation(
            now: now,
            windowDuration: remote?.windowDuration ?? configuration.windowDuration,
            cooldownDuration: remote?.cooldownDuration ?? configuration.cooldownDuration
        )
        switch decision {
        case let .open(window):
            let campaign = SpecialOfferCampaign(
                placementID: placementID,
                variationID: paywall.variationID,
                window: window,
                resolvedAt: now
            )
            // The decision presentation has served its purpose. The screen loads
            // the placement for itself, so the presentation it renders is its
            // own and is ended by whoever shows it.
            await end(paywall)
            return .campaign(campaign)
        case .cooldown:
            return await refuse(.cooldown, endingPresentationOf: paywall)
        case .unwritable:
            return await refuse(.persistenceUnavailable, endingPresentationOf: paywall)
        }
    }

    func refuse(
        _ refusal: SpecialOfferCampaignRefusal,
        endingPresentationOf paywall: PaywallPayload
    ) async -> SpecialOfferCampaignOutcome {
        // Whoever refuses a presentation ends it. Left open, it would hold the
        // placement for the rest of the session.
        await end(paywall)
        return .unavailable(refusal)
    }

    func end(_ paywall: PaywallPayload) async {
        await presentationLifecycle.presentationDidEnd(
            PaywallAnalyticsContext(paywall: paywall)
        )
    }
}
