public struct ResolveCheckoutMethodsUseCase: ResolveCheckoutMethodsUseCaseProtocol {
    private let storefrontRepository: any StorefrontRepositoryProtocol
    private let catalogRepository: any RUCatalogRepositoryProtocol
    private let productMatcher: RUCatalogProductMatcher
    private let gate: RUBillingGate

    public init(
        storefrontRepository: any StorefrontRepositoryProtocol,
        catalogRepository: any RUCatalogRepositoryProtocol,
        productMatcher: RUCatalogProductMatcher = RUCatalogProductMatcher(),
        isFeatureEnabled: Bool,
        remoteGateFallback: RUBillingRemoteGateFallbackPolicy = .disabled
    ) {
        self.storefrontRepository = storefrontRepository
        self.catalogRepository = catalogRepository
        self.productMatcher = productMatcher
        gate = RUBillingGate(
            isFeatureEnabled: isFeatureEnabled,
            remoteFallback: remoteGateFallback
        )
    }

    public func callAsFunction(
        for product: MonetizationProduct,
        remoteConfiguration: RemotePaywallConfiguration
    ) async -> CheckoutMethodsResolution {
        guard product.isEligibleForGenericPurchase else {
            return CheckoutMethodsResolution(methods: [], storefront: nil)
        }

        var methods: [CheckoutMethod] = product.catalogSource == .ruBackend ? [] : [.apple]

        guard gate.mayBeEligible(remoteConfiguration: remoteConfiguration) else {
            return CheckoutMethodsResolution(methods: methods, storefront: nil)
        }
        guard case let .available(storefront) = await storefrontRepository.currentStorefront() else {
            return CheckoutMethodsResolution(methods: methods, storefront: nil)
        }
        guard gate.allows(
            remoteConfiguration: remoteConfiguration,
            storefront: storefront
        ) else {
            return CheckoutMethodsResolution(methods: methods, storefront: storefront)
        }
        guard case let .loaded(catalog) = await catalogRepository.loadCatalog(),
              let matched = productMatcher.matchPremiumEntitlementProduct(
                  product,
                  in: catalog
              )
        else {
            return CheckoutMethodsResolution(methods: methods, storefront: storefront)
        }

        for method in matched.supportedMethods where !methods.contains(method) {
            methods.append(method)
        }
        return CheckoutMethodsResolution(methods: methods, storefront: storefront)
    }
}
