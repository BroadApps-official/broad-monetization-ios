import Foundation

@main
enum SpecialOfferRuntimeProbe {
    static func main() {
        checkRemoteFeatureCapabilities()
        check(elapsed: 0, expected: 86400)
        check(elapsed: 1, expected: 86399)
        check(elapsed: 86399, expected: 1)
        check(elapsed: 86400, expected: 0)
        check(elapsed: 86401, expected: 0)
        check(elapsed: 172_800, expected: 0)
        print(
            "PASS: the ordinary paywall authorizes Special Offer without weakening RU Billing; "
                + "the 24-hour countdown expires at zero and does not loop"
        )
    }

    private static func checkRemoteFeatureCapabilities() {
        let enabledOffer = SpecialOfferRemoteConfiguration(isEnabled: true)
        let parsedConfiguration = RemotePaywallConfiguration(
            isRUBillingEnabled: true,
            specialOffer: enabledOffer
        )
        let presentationID = PaywallPresentationID(rawValue: "runtime-probe")
        let gatePresentationID = PaywallPresentationID(rawValue: "gate-runtime-probe")
        let startedAt = Date(timeIntervalSinceReferenceDate: 1000)
        let window = SpecialOfferWindow(
            startedAt: startedAt,
            expiresAt: startedAt.addingTimeInterval(86400)
        )
        guard case let .synchronized(trustedTime) = SpecialOfferClockReading.trusted(startedAt)
        else {
            fatalError("A finite trusted time must synchronize")
        }

        let providerPayloadConfiguration = parsedConfiguration.qualified(
            by: .providerCacheFallbackPossible
        )
        guard providerPayloadConfiguration.specialOffer?.isEnabled == true,
              !providerPayloadConfiguration.authorizesRUBillingPresentation,
              SpecialOfferPresentationAuthorization(
                  paywallPresentationID: presentationID,
                  gatePaywallPresentationID: gatePresentationID,
                  gateRemoteConfiguration: providerPayloadConfiguration,
                  provenance: .providerCacheFallbackPossible,
                  window: window,
                  trustedTime: trustedTime
              ) != nil
        else {
            fatalError(
                "A standard provider payload must authorize Special Offer but not RU Billing"
            )
        }

        let verifiedConfiguration = parsedConfiguration.qualified(
            by: .verifiedFreshRemote
        )
        guard verifiedConfiguration.specialOffer?.isEnabled == true,
              verifiedConfiguration.authorizesRUBillingPresentation
        else {
            fatalError("Verified-fresh remote payload must retain both explicit gates")
        }

        let platformCacheConfiguration = parsedConfiguration.qualified(
            by: .platformCache
        )
        guard platformCacheConfiguration.specialOffer == nil,
              !platformCacheConfiguration.authorizesRUBillingPresentation,
              SpecialOfferPresentationAuthorization(
                  paywallPresentationID: presentationID,
                  gatePaywallPresentationID: gatePresentationID,
                  gateRemoteConfiguration: platformCacheConfiguration,
                  provenance: .platformCache,
                  window: window,
                  trustedTime: trustedTime
              ) == nil
        else {
            fatalError("Platform cache must not authorize Special Offer or RU Billing")
        }

        let missingGateConfiguration = RemotePaywallConfiguration.empty.qualified(
            by: .providerCacheFallbackPossible
        )
        guard missingGateConfiguration.specialOffer == nil,
              SpecialOfferPresentationAuthorization(
                  paywallPresentationID: presentationID,
                  gatePaywallPresentationID: gatePresentationID,
                  gateRemoteConfiguration: missingGateConfiguration,
                  provenance: .providerCacheFallbackPossible,
                  window: window,
                  trustedTime: trustedTime
              ) == nil
        else {
            fatalError("A missing special_offer gate must fail closed")
        }
    }

    private static func check(
        elapsed: TimeInterval,
        expected: TimeInterval
    ) {
        let actual = SpecialOfferCountdownAuthorization.remainingTimeInterval(
            elapsed: elapsed
        )
        guard actual == expected else {
            fatalError(
                "Unexpected countdown value at \(elapsed): \(actual), expected \(expected)"
            )
        }
    }
}
