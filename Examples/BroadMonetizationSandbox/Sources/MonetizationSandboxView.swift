import BroadMonetization
import SwiftUI

struct MonetizationSandboxView: View {
    private let parsedConfiguration = RemotePaywallConfigurationParser().parse([
        "special_offer": true,
        "ru_pay": true,
        "special_offer_badge": "Fixture"
    ])

    private let products = [
        MonetizationProduct(
            presentationID: .generated(),
            reference: ProductReference(rawValue: "fixture-product-occurrence-a"),
            productID: ProductID(rawValue: "fixture-product-a"),
            kind: .autoRenewableSubscription,
            title: "Fixture monthly",
            price: Money(amount: 199, currencyCode: "RUB"),
            displayPrice: "provider value",
            subscriptionPeriod: .month(),
            catalogSource: .adapty
        ),
        MonetizationProduct(
            presentationID: .generated(),
            reference: ProductReference(rawValue: "fixture-product-occurrence-b"),
            productID: ProductID(rawValue: "fixture-product-b"),
            kind: .autoRenewableSubscription,
            title: "Fixture yearly",
            price: Money(amount: 1490, currencyCode: "RUB"),
            displayPrice: "provider value",
            subscriptionPeriod: .year(),
            catalogSource: .adapty
        )
    ]

    var body: some View {
        NavigationStack {
            List {
                Section("Parsed products first") {
                    LabeledContent("Provider occurrences", value: "\(products.count)")
                    LabeledContent("Order", value: "preserved")
                    LabeledContent("Raw references", value: "exact")
                }

                Section("Special Offer authority") {
                    LabeledContent(
                        "Provider payload",
                        value: yesNo(providerConfiguration.specialOffer?.isEnabled == true)
                    )
                    LabeledContent(
                        "Platform cache",
                        value: yesNo(platformCacheConfiguration.specialOffer?.isEnabled == true)
                    )
                    LabeledContent("Countdown", value: "24:00:00 → 00:00:00 → loop")
                }

                Section("RU Billing authority") {
                    LabeledContent(
                        "Provider payload",
                        value: yesNo(
                            PaywallRemoteConfigurationProvenance
                                .providerCacheFallbackPossible
                                .authorizesRUBillingPresentation
                        )
                    )
                    LabeledContent(
                        "Verified fresh",
                        value: yesNo(
                            PaywallRemoteConfigurationProvenance
                                .verifiedFreshRemote
                                .authorizesRUBillingPresentation
                        )
                    )
                }

                Section("Safety") {
                    Text("Fixture-only: SDK activation, purchase, restore and RU payment are not executed.")
                }
            }
            .navigationTitle("BroadMonetization")
        }
    }

    private var providerConfiguration: RemotePaywallConfiguration {
        qualifiedConfiguration(for: .providerCacheFallbackPossible)
    }

    private var platformCacheConfiguration: RemotePaywallConfiguration {
        qualifiedConfiguration(for: .platformCache)
    }

    private func qualifiedConfiguration(
        for provenance: PaywallRemoteConfigurationProvenance
    ) -> RemotePaywallConfiguration {
        PaywallPayload(
            presentationID: .generated(),
            paywallReference: PaywallReference(rawValue: "fixture-paywall"),
            origin: PaywallOrigin(
                requestedPlacementID: PlacementID(rawValue: "fixture-placement"),
                resolvedPlacementID: PlacementID(rawValue: "fixture-placement"),
                catalogSource: .adapty
            ),
            products: products,
            remoteConfiguration: parsedConfiguration,
            remoteConfigurationProvenance: provenance,
            fetchedAt: Date()
        ).remoteConfiguration
    }

    private func yesNo(_ value: Bool) -> String {
        value ? "yes" : "no"
    }
}
