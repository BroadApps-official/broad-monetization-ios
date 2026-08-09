public protocol StartSelectedRUCheckoutUseCaseProtocol: Sendable {
    func callAsFunction(
        _ selection: ProductSelection,
        using checkoutMethod: CheckoutMethod,
        remoteConfiguration: RemotePaywallConfiguration
    ) async -> RUCheckoutFlowOutcome
}

/// Resolves the selected occurrence to an exact backend catalog row before the
/// checkout coordinator performs its independent live-storefront gate.
actor StartSelectedRUCheckoutUseCase:
    StartSelectedRUCheckoutUseCaseProtocol {
    private let catalogRepository: any RUCatalogRepositoryProtocol
    private let matcher: RUCatalogProductMatcher
    private let checkoutFlow: RUCheckoutFlowCoordinator

    private var isStarting = false

    init(
        catalogRepository: any RUCatalogRepositoryProtocol,
        matcher: RUCatalogProductMatcher = RUCatalogProductMatcher(),
        checkoutFlow: RUCheckoutFlowCoordinator
    ) {
        self.catalogRepository = catalogRepository
        self.matcher = matcher
        self.checkoutFlow = checkoutFlow
    }

    func callAsFunction(
        _ selection: ProductSelection,
        using checkoutMethod: CheckoutMethod,
        remoteConfiguration: RemotePaywallConfiguration
    ) async -> RUCheckoutFlowOutcome {
        guard selection.product.isEligibleForGenericPurchase else {
            return .unavailable(RUBillingSafeErrors.checkoutNotEligible)
        }
        guard checkoutMethod == .sbp || checkoutMethod == .card else {
            return .unavailable(RUBillingSafeErrors.checkoutNotEligible)
        }
        guard !isStarting else {
            return .unavailable(RUBillingSafeErrors.checkoutUnavailable)
        }

        isStarting = true
        defer { isStarting = false }

        guard case let .loaded(catalog) = await catalogRepository.loadCatalog(),
              let matchedProduct = matcher.matchPremiumEntitlementProduct(
                  selection.product,
                  in: catalog
              ),
              matchedProduct.supportedMethods.contains(checkoutMethod)
        else {
            return .unavailable(RUBillingSafeErrors.catalogUnavailable)
        }

        return await checkoutFlow.start(
            RUCheckoutRequest(
                productID: matchedProduct.catalogProductID,
                method: checkoutMethod,
                acceptsAutoRenewal:
                selection.product.kind == .autoRenewableSubscription
            ),
            selection: selection,
            remoteConfiguration: remoteConfiguration
        )
    }
}
