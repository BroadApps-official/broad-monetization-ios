import Foundation

public struct SpecialOfferPresentationAuthorization: Equatable, Sendable {
    public let paywallPresentationID: PaywallPresentationID
    public let gatePaywallPresentationID: PaywallPresentationID
    public let gateRemoteConfiguration: RemotePaywallConfiguration
    public let remoteConfiguration: SpecialOfferRemoteConfiguration
    public let countdown: SpecialOfferCountdownAuthorization
    public let expiresAt: Date

    init?(
        paywallPresentationID: PaywallPresentationID,
        gatePaywallPresentationID: PaywallPresentationID,
        gateRemoteConfiguration: RemotePaywallConfiguration,
        provenance: PaywallRemoteConfigurationProvenance,
        window: SpecialOfferWindow,
        trustedTime: SpecialOfferTrustedTime
    ) {
        // The gate is intentionally supplied by the ordinary paywall. The
        // presentation ID belongs to the separate offer payload and cannot be
        // substituted with that ordinary paywall.
        guard provenance.authorizesSpecialOfferPresentation,
              let specialOffer = gateRemoteConfiguration.specialOffer,
              specialOffer.isEnabled
        else {
            return nil
        }

        self.paywallPresentationID = paywallPresentationID
        self.gatePaywallPresentationID = gatePaywallPresentationID
        self.gateRemoteConfiguration = gateRemoteConfiguration
        remoteConfiguration = specialOffer
        countdown = SpecialOfferCountdownAuthorization(
            window: window,
            trustedTime: trustedTime
        )
        expiresAt = window.expiresAt
    }
}
