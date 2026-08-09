public struct DisabledRUBillingCheckoutMethodsUseCase: ResolveCheckoutMethodsUseCaseProtocol {
    public init() {}

    public func callAsFunction(
        for product: MonetizationProduct,
        remoteConfiguration _: RemotePaywallConfiguration
    ) async -> CheckoutMethodsResolution {
        CheckoutMethodsResolution(
            methods: product.catalogSource == .ruBackend ? [] : [.apple],
            storefront: nil
        )
    }
}

public struct DisabledSelectedRUCheckoutUseCase:
    StartSelectedRUCheckoutUseCaseProtocol {
    public init() {}

    public func callAsFunction(
        _: ProductSelection,
        using _: CheckoutMethod,
        remoteConfiguration _: RemotePaywallConfiguration
    ) async -> RUCheckoutFlowOutcome {
        .unavailable(RUBillingSafeErrors.notConfigured)
    }
}
