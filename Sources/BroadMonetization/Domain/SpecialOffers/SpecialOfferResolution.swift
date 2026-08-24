import Foundation

public struct SpecialOfferResolution: Equatable, Sendable {
    public let state: SpecialOfferState
    public let paywall: PaywallPayload?
    public let presentationAuthorization: SpecialOfferPresentationAuthorization?

    public init(
        state: SpecialOfferState,
        paywall: PaywallPayload?,
        trustedTime _: SpecialOfferTrustedTime? = nil
    ) {
        let authorization: SpecialOfferPresentationAuthorization?
        switch state {
        case .eligible, .active:
            precondition(
                paywall != nil,
                "A presentable special offer requires its paywall payload"
            )
            authorization = Self.makeAuthorization(paywall: paywall)
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
        paywall: PaywallPayload?
    ) -> SpecialOfferPresentationAuthorization {
        guard let paywall,
              paywall.remoteConfigurationProvenance
              .authorizesSpecialOfferPresentation,
              paywall.remoteConfiguration.specialOffer?.isEnabled == true
        else {
            preconditionFailure(
                "Special-offer presentation requires an enabled provider payload"
            )
        }
        guard let authorization = SpecialOfferPresentationAuthorization(
            paywallPresentationID: paywall.presentationID,
            specialOffer: paywall.remoteConfiguration.specialOffer,
            provenance: paywall.remoteConfigurationProvenance
        ) else {
            preconditionFailure(
                "Special-offer presentation requires an enabled provider payload"
            )
        }
        return authorization
    }
}
