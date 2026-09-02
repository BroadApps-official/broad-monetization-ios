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
        provenance: PaywallRemoteConfigurationProvenance,
        window: SpecialOfferWindow? = nil,
        trustedTime: SpecialOfferTrustedTime? = nil
    ) {
        // Absence means the campaign is on: only an explicit `false` from the
        // provider payload stops the offer.
        guard provenance.authorizesSpecialOfferPresentation,
              specialOffer?.isEnabled != false
        else {
            return nil
        }

        self.paywallPresentationID = paywallPresentationID
        if let window, let trustedTime {
            countdown = SpecialOfferCountdownAuthorization(
                window: window,
                trustedTime: trustedTime
            )
        } else {
            countdown = SpecialOfferCountdownAuthorization()
        }
    }
}
