import Foundation

public struct SpecialOfferResolution: Equatable, Sendable {
    public let state: SpecialOfferState
    public let paywall: PaywallPayload?
    public let presentationAuthorization: SpecialOfferPresentationAuthorization?

    public init(
        state: SpecialOfferState,
        paywall: PaywallPayload?,
        trustedTime: SpecialOfferTrustedTime? = nil,
        gatePaywall: PaywallPayload? = nil
    ) {
        let authorization: SpecialOfferPresentationAuthorization?
        switch state {
        case let .active(window):
            precondition(
                paywall != nil && trustedTime != nil,
                "An active special offer requires its paywall payload and trusted time"
            )
            authorization = Self.makeAuthorization(
                paywall: paywall,
                gatePaywall: gatePaywall ?? paywall,
                window: window,
                trustedTime: trustedTime
            )
        case .unavailable, .eligible, .expired, .cooldown:
            precondition(
                paywall == nil,
                "A non-active special offer must not carry a paywall payload"
            )
            authorization = nil
        }

        self.state = state
        self.paywall = paywall
        presentationAuthorization = authorization
    }

    private static func makeAuthorization(
        paywall: PaywallPayload?,
        gatePaywall: PaywallPayload?,
        window: SpecialOfferWindow,
        trustedTime: SpecialOfferTrustedTime?
    ) -> SpecialOfferPresentationAuthorization {
        guard let paywall,
              let gatePaywall,
              let trustedTime,
              gatePaywall.remoteConfigurationProvenance
              .authorizesSpecialOfferPresentation,
              gatePaywall.remoteConfiguration.specialOffer?.isEnabled == true
        else {
            preconditionFailure(
                "Special-offer presentation requires an authorized ordinary-paywall gate"
            )
        }
        guard let authorization = SpecialOfferPresentationAuthorization(
            paywallPresentationID: paywall.presentationID,
            gatePaywallPresentationID: gatePaywall.presentationID,
            gateRemoteConfiguration: gatePaywall.remoteConfiguration,
            provenance: gatePaywall.remoteConfigurationProvenance,
            window: window,
            trustedTime: trustedTime
        ) else {
            preconditionFailure(
                "Special-offer presentation requires an authorized ordinary-paywall gate"
            )
        }
        return authorization
    }
}
