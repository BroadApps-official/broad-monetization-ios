import BroadCore
import Foundation

/// Compatibility adapter for the campaign-shaped API. It follows the same
/// contract as ``ResolveSpecialOfferUseCase``: the ordinary paywall owns the
/// strict boolean gate and the separate campaign placement owns the products.
///
/// How often an offer may be shown is the platform's rule here, not the host's:
/// a day of offer, then a quiet day, measured on server time
/// (`ServerTimeProviderProtocol`) so the cadence cannot be moved with the
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

        let gateOutcome = await loadPaywallUseCase(
            PaywallLoadRequest(placementID: configuration.gatePlacementID)
        )
        guard case let .loaded(gatePaywall) = gateOutcome else {
            return .unavailable(.placementUnavailable)
        }
        guard !gatePaywall.origin.usedFallback,
              gatePaywall.origin.requestedPlacementID == configuration.gatePlacementID,
              gatePaywall.origin.resolvedPlacementID == configuration.gatePlacementID,
              gatePaywall.remoteConfigurationProvenance.authorizesSpecialOfferPresentation
        else {
            return await refuse(.substitutedPaywall, endingPresentationOf: gatePaywall)
        }
        guard gatePaywall.remoteConfiguration.specialOffer?.isEnabled == true else {
            await windowRepository.clear()
            return await refuse(.disabledRemotely, endingPresentationOf: gatePaywall)
        }
        await end(gatePaywall)

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
        reading.isSynchronized ? reading.date : nil
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

        // An empty campaign must not spend the day: the window would open on a
        // screen with nothing on it, and the quiet day that follows would hide
        // the real offer once the placement is filled in.
        guard !paywall.products.isEmpty else {
            return await refuse(.emptyCatalog, endingPresentationOf: paywall)
        }

        let decision = await windowRepository.windowForPresentation(
            now: now,
            windowDuration: SpecialOfferCampaignConfiguration.defaultWindowDuration,
            cooldownDuration: SpecialOfferCampaignConfiguration.defaultCooldownDuration
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
