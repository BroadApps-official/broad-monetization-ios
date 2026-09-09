import BroadCore
import Foundation

extension RUProviderFallbackProbe {
    static let defaultCatalog = RUCatalogPayload(products: [
        Catalog.row(90, identifier: "ordinary", appleID: "apple-match"),
        Catalog.row(100, isDefault: true),
        Catalog.row(300, offer: true, isDefault: true),
        Catalog.row(200, isDefault: true),
        Catalog.row(500, kind: .tokens, isDefault: true)
    ], fetchedAt: Date())

    static func providerPayload(
        identifiers: [String], configuration: RemotePaywallConfiguration = .init(isRUBillingEnabled: true),
        provenance: PaywallRemoteConfigurationProvenance = .verifiedFreshRemote
    ) -> PaywallPayload {
        PaywallPayload(
            presentationID: .generated(), paywallReference: .init(rawValue: "adapty-defaults-fixture"),
            origin: .init(requestedPlacementID: .main, resolvedPlacementID: .main, catalogSource: .adapty),
            products: identifiers.map { identifier in
                MonetizationProduct(
                    presentationID: .generated(), reference: .init(rawValue: "sdk-handle-\(identifier)"),
                    productID: .init(rawValue: identifier), kind: .autoRenewableSubscription,
                    price: Money(amount: 9, currencyCode: "USD"),
                    subscriptionPeriod: .init(unit: .month, count: 1), catalogSource: .adapty
                )
            },
            remoteConfiguration: configuration, remoteConfigurationProvenance: provenance, fetchedAt: Date()
        )
    }

    static func defaultProductContracts() async {
        // Outage, successful [], and a live non-matching Adapty catalog must all
        // select the same two defaults, retaining their original row indices.
        for provider in [
            Provider(response: nil),
            Provider(response: nil, supplied: providerPayload(identifiers: [])),
            Provider(response: nil, supplied: providerPayload(identifiers: ["missing"]))
        ] {
            let catalog = Catalog(supplied: defaultCatalog)
            let payload = await loaded(loader(provider: provider, catalog: catalog)(.init(placementID: .main)))
            check(payload.origin.catalogSource == .ruBackend)
            check(payload.products.map(\.price?.amount) == [100, 200])
            check(payload.products.map(\.reference.rawValue) == ["ru-fallback-row-1", "ru-fallback-row-3"])
            let selected = payload.products[1]
            check(RUCatalogProductMatcher().matchPremiumEntitlementProduct(selected, in: defaultCatalog)?.price?.amount == 200)
            let methods = ResolveCheckoutMethodsUseCase(
                storefrontRepository: Store(region: "RU"), catalogRepository: catalog,
                isFeatureEnabled: true, deviceContextProvider: Device(region: "US")
            )
            let resolution = await methods(for: selected, remoteConfiguration: payload.remoteConfiguration)
            check(resolution.methods.contains(.card) && !resolution.methods.contains(.apple))
            await check(catalog.freshCalls == 2)
            await check(catalog.cachedCalls == 0)
        }
        // One or more exact matches win over defaults; keep the provider array
        // and SDK handles intact, even when another product has no RU match.
        for ids in [["ordinary"], ["apple-match", "missing", "apple-match"]] {
            let normal = providerPayload(identifiers: ids)
            let catalog = Catalog(supplied: defaultCatalog)
            let result =
                await loaded(loader(provider: Provider(response: nil, supplied: normal), catalog: catalog)(.init(placementID: .main)))
            check(result.origin.catalogSource == .adapty && result.products == normal.products)
            await check(catalog.freshCalls == 1)
        }
        // Legacy backend JSON without defaults keeps its complete subscription section.
        let legacy = await loaded(loader(
            provider: Provider(response: nil, supplied: providerPayload(identifiers: ["missing"])), catalog: Catalog()
        )(.init(placementID: .main)))
        check(legacy.origin.catalogSource == .ruBackend && legacy.products.map(\.price?.amount) == [100, 200])
        for config in [
            RemotePaywallConfiguration.empty,
            .init(isRUBillingEnabled: false),
            RemotePaywallConfigurationParser().parse(["ru_pay": "broken"])
        ] {
            let catalog = Catalog(supplied: defaultCatalog)
            let normal = providerPayload(identifiers: ["missing"], configuration: config)
            let result =
                await loaded(loader(provider: Provider(response: nil, supplied: normal), catalog: catalog)(.init(placementID: .main)))
            check(result.origin.catalogSource == .adapty)
            await check(catalog.freshCalls == 0)
        }
        for provenance in [PaywallRemoteConfigurationProvenance.legacyUnqualified, .platformCache] {
            let catalog = Catalog(supplied: defaultCatalog)
            _ = await loader(provider: Provider(response: nil, supplied: providerPayload(
                identifiers: ["missing"], provenance: provenance
            )), catalog: catalog)(.init(placementID: .main))
            await check(catalog.freshCalls == 0)
        }
        let nonRussian = Catalog(supplied: defaultCatalog)
        _ = await loader(
            provider: Provider(response: nil, supplied: providerPayload(identifiers: ["missing"])),
            catalog: nonRussian,
            region: "US",
            store: "US"
        )(.init(placementID: .main))
        await check(nonRussian.freshCalls == 0)
        print("RU defaults passed: outage/empty/no matches, all defaults, original row identity, exact-match priority and gates.")
    }
}
