import BroadCore
import Foundation

@main
enum RUProviderFallbackProbe {
    static let error = AppError(
        kind: .unavailable,
        userMessage: "Fixture unavailable",
        diagnosticCode: "fixture.offline",
        isRetryable: true
    )

    static func main() async throws {
        for region in [nil, "US", "RU", "RUS"] as [String?] {
            for store in [nil, "US", "RU", "RUS"] as [String?] {
                for response in [
                    nil,
                    .empty,
                    .init(isRUBillingEnabled: false),
                    .init(isRUBillingEnabled: true),
                    RemotePaywallConfigurationParser().parse(["ru_pay": "broken"])
                ] as [RemotePaywallConfiguration?] {
                    let catalog = Catalog()
                    let outcome = await loader(
                        provider: Provider(response: response),
                        catalog: catalog,
                        region: region,
                        store: store
                    )(.init(placementID: .main))
                    let shouldLoad = (region == "RU" || region == "RUS" || store == "RU" || store == "RUS")
                        && (response == nil || response?.ruBillingGateDecision == .enabled)
                    await check(catalog.freshCalls == (shouldLoad ? 1 : 0))
                    if shouldLoad {
                        try inspect(loaded(outcome))
                    } else {
                        if case .loaded = outcome {
                            fatalError("Forbidden fallback")
                        }
                    }
                }
            }
        }
        await failureAndCacheContracts()
        await selectionContracts()
        await placementAndCancellationContracts()
        await missingPlacementContracts()
        await dedicatedPlacementContracts()
        print(
            "RU provider fallback passed: regional/response matrix, false after products failure, fresh catalog, row identity, cache, cancellation."
        )
    }

    static func inspect(_ payload: PaywallPayload) throws {
        check(payload.origin.catalogSource == .ruBackend)
        check(payload.products.count == 3) // duplicated subscription plus unknown, no offer
        check(payload.products[0].productID == payload.products[1].productID)
        check(payload.products[0].presentationID != payload.products[1].presentationID)
        check(payload.products[2].isEligibleForGenericPurchase == false)
        check(payload.remoteConfiguration.isRUBillingEnabled == nil)
        check(payload.remoteConfiguration.ruExperiment == nil && payload.remoteConfiguration.specialOffer == nil)
        let gate = RUBillingGate(isFeatureEnabled: true, deviceContextProvider: Device(region: "RU"))
        check(gate.allows(remoteConfiguration: payload.remoteConfiguration))
        let decoded = try JSONDecoder().decode(PaywallPayload.self, from: JSONEncoder().encode(payload))
        check(!gate.allows(remoteConfiguration: decoded.remoteConfiguration))
        check(!gate.allows(remoteConfiguration: payload.remoteConfiguration.qualified(by: .platformCache)))
        check(!RUBillingGate(isFeatureEnabled: false).allows(remoteConfiguration: payload.remoteConfiguration))
    }

    static func failureAndCacheContracts() async {
        let failedCatalog = Catalog(unavailable: true)
        let failed = await loader(provider: Provider(response: nil), catalog: failedCatalog)(.init(placementID: .main))
        if case .loaded = failed {
            fatalError("Offline backend must not fabricate products")
        }
        await check(failedCatalog.cachedCalls == 0)
        let normal = PaywallPayload(
            presentationID: .generated(), paywallReference: .init(rawValue: "provider-fixture"),
            origin: .init(requestedPlacementID: .main, resolvedPlacementID: .main, catalogSource: .adapty),
            products: RUFallbackProductIdentity.products(in: Catalog.payload),
            remoteConfiguration: .init(isRUBillingEnabled: true), fetchedAt: Date()
        )
        let catalog = Catalog()
        let ordinary = await loader(provider: Provider(response: nil, supplied: normal), catalog: catalog)(.init(placementID: .main))
        check(loaded(ordinary).origin.catalogSource == .adapty)
        await check(catalog.freshCalls == 0)
        let restored = await loader(
            provider: Provider(response: nil),
            catalog: catalog,
            cache: Cache(payload: normal)
        )(.init(placementID: .main))
        check(loaded(restored).origin.catalogSource == .ruBackend)
        let denied = await loader(
            provider: Provider(response: .init(isRUBillingEnabled: false)),
            catalog: catalog,
            cache: Cache(payload: normal)
        )(.init(placementID: .main))
        check(loaded(denied).origin.catalogSource == .cache)
        check(!RUBillingGate(isFeatureEnabled: true, deviceContextProvider: Device(region: "RU"))
            .allows(remoteConfiguration: loaded(denied).remoteConfiguration))
        await check(catalog.freshCalls == 1)
    }

    static func selectionContracts() async {
        let catalog = Catalog()
        let payload = await loaded(loader(provider: Provider(response: nil), catalog: catalog)(.init(placementID: .main)))
        let selected = payload.products[1]
        let matcher = RUCatalogProductMatcher()
        check(matcher.matchPremiumEntitlementProduct(selected, in: Catalog.payload)?.price?.amount == 200)
        let changed = RUCatalogPayload(products: Catalog.payload.products.reversed(), fetchedAt: Date())
        check(matcher.matchPremiumEntitlementProduct(selected, in: changed) == nil)
        let methods = ResolveCheckoutMethodsUseCase(
            storefrontRepository: Store(region: "RU"), catalogRepository: catalog,
            isFeatureEnabled: true, deviceContextProvider: Device(region: "US")
        )
        let resolution = await methods(for: selected, remoteConfiguration: payload.remoteConfiguration)
        check(!resolution.methods.contains(.apple) && resolution.methods.contains(.card))
        let counts = await (catalog.cachedCalls, catalog.freshCalls)
        check(counts.0 == 0 && counts.1 == 2)
    }

    static func placementAndCancellationContracts() async {
        let catalog = Catalog()
        let fallback = loader(provider: Provider(response: nil), catalog: catalog)
        _ = await fallback(.init(placementID: .specialOffer))
        await check(catalog.freshCalls == 0)
        let disabled = Provider(response: nil, firstResponse: .init(isRUBillingEnabled: false))
        _ = await loader(provider: disabled, catalog: catalog)(.init(placementID: PlacementID(rawValue: "onboarding")))
        await check(catalog.freshCalls == 0)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await fallback(.init(placementID: .main))
        }
        _ = await task.value
        await check(catalog.freshCalls == 0)
        async let allowed = fallback(.init(placementID: .main))
        async let prohibited = loader(provider: disabled, catalog: catalog)(.init(placementID: PlacementID(rawValue: "onboarding")))
        _ = await (allowed, prohibited)
        await check(catalog.freshCalls == 1)
    }

    static func missingPlacementContracts() async {
        let catalog = Catalog()
        let optional = PlacementID(rawValue: "unconfigured-optional")
        let provider = Provider(response: nil, notConfigured: optional)
        let outcome = await loader(provider: provider, catalog: catalog)(.init(placementID: optional))
        check(loaded(outcome).origin.catalogSource == .ruBackend)
        await check(catalog.freshCalls == 1)
        let missingMain = Provider(response: nil, notConfigured: .main)
        _ = await loader(provider: missingMain, catalog: catalog)(.init(placementID: optional))
        await check(catalog.freshCalls == 1)
    }

    static func dedicatedPlacementContracts() async {
        for placement in [PlacementID.tokens, .specialOffer] {
            let provider = DedicatedPlacementProvider()
            let ordinary = LoadPaywallUseCase(
                repository: provider, analytics: NoOpMonetizationAnalytics(), staleLoadError: error
            )
            let result = await ordinary(.init(placementID: placement))
            if case .loaded = result {
                fatalError("Dedicated placement must not borrow main products")
            }
            await check(provider.calls == [placement])
            let catalog = Catalog()
            let fallback = LoadPaywallWithRUFallbackUseCase(
                provider: provider, catalog: catalog, storefront: Store(region: "RU"),
                gate: RUBillingGate(isFeatureEnabled: true, deviceContextProvider: Device(region: "RU")),
                analytics: NoOpMonetizationAnalytics(), staleLoadError: error
            )
            let reserved = await fallback(.init(placementID: placement))
            if case .loaded = reserved {
                fatalError("Dedicated placement must not borrow RU subscription products")
            }
            await check(provider.calls == [placement, placement])
            await check(catalog.freshCalls == 0)
        }
    }

    static func loader(
        provider: Provider, catalog: Catalog, region: String? = "RU", store: String? = nil, cache: Cache? = nil
    ) -> LoadPaywallWithRUFallbackUseCase {
        LoadPaywallWithRUFallbackUseCase(
            provider: provider, catalog: catalog, storefront: Store(region: store),
            gate: RUBillingGate(isFeatureEnabled: true, deviceContextProvider: Device(region: region)),
            cache: cache, analytics: NoOpMonetizationAnalytics(), staleLoadError: error
        )
    }

    static func loaded(_ outcome: PaywallLoadOutcome) -> PaywallPayload {
        guard case let .loaded(payload) = outcome else { fatalError("Expected backend paywall") }
        return payload
    }

    static func check(_ value: Bool, line: UInt = #line) {
        precondition(value, "Fallback contract failed at line \(line)")
    }
}

extension RUProviderFallbackProbe {
    struct Provider: RUFallbackPaywallRepositoryProtocol {
        let response: RemotePaywallConfiguration?
        var firstResponse: RemotePaywallConfiguration?
        var supplied: PaywallPayload?
        var notConfigured: PlacementID?
        func loadPaywall(for _: PlacementID) async -> PaywallLoadOutcome {
            .unavailable(error)
        }

        func loadRUFallbackAttempt(for placement: PlacementID) async -> RUFallbackPaywallAttempt {
            if placement == notConfigured {
                return RUFallbackPaywallAttempt(outcome: .unavailable(error), availability: .notConfigured)
            }
            if let supplied {
                return RUFallbackPaywallAttempt(outcome: .loaded(supplied), availability: .available)
            }
            return RUFallbackPaywallAttempt(
                outcome: .unavailable(error),
                availability: .unavailable(receivedConfiguration: placement == .main ? response : firstResponse ?? response)
            )
        }
    }

    actor DedicatedPlacementProvider: RUFallbackPaywallRepositoryProtocol {
        var calls: [PlacementID] = []
        func loadPaywall(for placementID: PlacementID) async -> PaywallLoadOutcome {
            await loadRUFallbackAttempt(for: placementID).outcome
        }

        func loadRUFallbackAttempt(for placementID: PlacementID) async -> RUFallbackPaywallAttempt {
            calls.append(placementID)
            if placementID == .main {
                let payload = PaywallPayload(
                    presentationID: .generated(), paywallReference: .init(rawValue: "main-fixture"),
                    origin: .init(requestedPlacementID: .main, resolvedPlacementID: .main, catalogSource: .adapty),
                    products: RUFallbackProductIdentity.products(in: Catalog.payload),
                    remoteConfiguration: .init(isRUBillingEnabled: true), fetchedAt: Date()
                )
                return .init(outcome: .loaded(payload), availability: .available)
            }
            return .init(outcome: .unavailable(error), availability: .unavailable(receivedConfiguration: nil))
        }
    }

    struct Device: RUBillingDeviceContextProviderProtocol {
        let region: String?
        func currentContext() -> RUBillingDeviceContext {
            .init(regionCode: region, primaryLanguageIdentifier: "ru")
        }
    }

    struct Store: StorefrontRepositoryProtocol {
        let region: String?
        func currentStorefront() async -> StorefrontResolution {
            region.map { .available(Storefront(countryCode: $0)) } ?? .unavailable(error)
        }
    }

    struct Cache: PaywallCacheProtocol {
        let payload: PaywallPayload
        func readPaywall(for _: PlacementID) async -> PaywallCacheReadOutcome {
            .stale(payload)
        }

        func writePaywall(_: PaywallPayload, for _: PlacementID) async -> PaywallCacheWriteOutcome {
            .stored
        }
    }

    actor Catalog: FreshRUCatalogRepositoryProtocol {
        let unavailable: Bool
        init(unavailable: Bool = false) {
            self.unavailable = unavailable
        }

        var freshCalls = 0
        var cachedCalls = 0
        static let payload = RUCatalogPayload(
            products: [row(100), row(200), row(300, offer: true), row(400, kind: .unknown)],
            fetchedAt: Date()
        )
        static func row(_ price: Decimal, offer: Bool = false, kind: RUCatalogProductKind = .subscription) -> RUCatalogProduct {
            RUCatalogProduct(
                catalogProductID: .init(rawValue: "same-id"),
                kind: kind,
                appStoreProductID: nil,
                price: Money(amount: price, currencyCode: "RUB"),
                displayPrice: nil,
                subscriptionPeriod: .init(unit: .month, count: 1),
                supportedMethods: [.card],
                isSpecialOffer: offer
            )
        }

        func loadCatalog() async -> RUCatalogLoadOutcome {
            cachedCalls += 1; return .loaded(Self.payload)
        }

        func loadFreshCatalog() async -> RUCatalogLoadOutcome {
            freshCalls += 1; return unavailable ? .unavailable(error) : .loaded(Self.payload)
        }
    }
}
