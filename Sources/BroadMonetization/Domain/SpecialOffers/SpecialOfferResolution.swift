import Foundation

public struct SpecialOfferResolution: Equatable, Sendable {
    public let state: SpecialOfferState
    public let paywall: PaywallPayload?
    public let presentationAuthorization: SpecialOfferPresentationAuthorization?

    public init(
        state: SpecialOfferState,
        paywall: PaywallPayload?,
        trustedTime: SpecialOfferTrustedTime? = nil
    ) {
        let authorization: SpecialOfferPresentationAuthorization?
        switch state {
        case .eligible:
            precondition(
                paywall != nil,
                "A presentable special offer requires its paywall payload"
            )
            authorization = Self.makeAuthorization(
                paywall: paywall,
                window: nil,
                trustedTime: nil
            )
        case let .active(window):
            precondition(
                paywall != nil,
                "A presentable special offer requires its paywall payload"
            )
            authorization = Self.makeAuthorization(
                paywall: paywall,
                window: window,
                trustedTime: trustedTime
            )
        case .unavailable, .expired, .cooldown:
            precondition(
                paywall == nil,
                "An unavailable special offer must not carry a paywall payload"
            )
            authorization = nil
        }

        self.state = state
        self.paywall = paywall
        presentationAuthorization = authorization
    }

    private static func makeAuthorization(
        paywall: PaywallPayload?,
        window: SpecialOfferWindow?,
        trustedTime: SpecialOfferTrustedTime?
    ) -> SpecialOfferPresentationAuthorization {
        // A presentable resolution requires the provider's explicit opt-in.
        guard let paywall,
              paywall.remoteConfigurationProvenance
              .authorizesSpecialOfferPresentation,
              paywall.remoteConfiguration.specialOffer?.isEnabled == true
        else {
            preconditionFailure(
                "Special-offer presentation requires an authorized provider payload"
            )
        }
        guard let authorization = SpecialOfferPresentationAuthorization(
            paywallPresentationID: paywall.presentationID,
            specialOffer: paywall.remoteConfiguration.specialOffer,
            provenance: paywall.remoteConfigurationProvenance,
            window: window,
            trustedTime: trustedTime
        ) else {
            preconditionFailure(
                "Special-offer presentation requires an authorized provider payload"
            )
        }
        return authorization
    }
}
