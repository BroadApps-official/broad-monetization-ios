import Foundation

public struct SpecialOfferPresentationAuthorization: Equatable, Sendable {
    public let paywallPresentationID: PaywallPresentationID
    public let countdown: SpecialOfferCountdownAuthorization?

    /// Compatibility property. The display countdown is not an expiration
    /// boundary, so a platform Special Offer has no runtime expiry date.
    @available(*, deprecated, message: "Special Offer no longer has a runtime expiration date")
    public var expiresAt: Date? {
        nil
    }

    init?(
        paywallPresentationID: PaywallPresentationID,
        specialOffer: SpecialOfferRemoteConfiguration?,
        provenance: PaywallRemoteConfigurationProvenance
    ) {
        guard provenance.authorizesSpecialOfferPresentation,
              specialOffer?.isEnabled == true
        else {
            return nil
        }

        self.paywallPresentationID = paywallPresentationID
        countdown = SpecialOfferCountdownAuthorization()
    }
}
