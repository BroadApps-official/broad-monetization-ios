/// Default composition for an app that installs only App Store billing.
public struct AppleCheckoutMethodsUseCase: ResolveCheckoutMethodsUseCaseProtocol {
    public init() {}
    public func callAsFunction(
        for product: MonetizationProduct,
        remoteConfiguration: RemotePaywallConfiguration
    ) async -> CheckoutMethodsResolution {
        let isAppleCatalog = [CatalogSource.adapty, .storeKit, .cache].contains(product.catalogSource)
        return CheckoutMethodsResolution(methods: isAppleCatalog && product.isEligibleForGenericPurchase ? [.apple] : [], storefront: nil)
    }
}
