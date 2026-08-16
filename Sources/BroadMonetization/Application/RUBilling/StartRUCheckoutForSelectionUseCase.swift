public protocol StartSelectedRUCheckoutUseCaseProtocol: Sendable {
    func callAsFunction(
        _ selection: ProductSelection,
        using checkoutMethod: CheckoutMethod,
        remoteConfiguration: RemotePaywallConfiguration,
        options: CheckoutOptions
    ) async -> RUCheckoutFlowOutcome
}

public extension StartSelectedRUCheckoutUseCaseProtocol {
    func callAsFunction(
        _ selection: ProductSelection,
        using checkoutMethod: CheckoutMethod,
        remoteConfiguration: RemotePaywallConfiguration
    ) async -> RUCheckoutFlowOutcome {
        await callAsFunction(
            selection,
            using: checkoutMethod,
            remoteConfiguration: remoteConfiguration,
            options: .standard
        )
    }
}

/// Resolves the selected occurrence to an exact backend catalog row before the
/// checkout coordinator independently rechecks `ru_pay` and the iPhone context.
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
        remoteConfiguration: RemotePaywallConfiguration,
        options: CheckoutOptions
    ) async -> RUCheckoutFlowOutcome {
        guard selection.product.isEligibleForGenericPurchase else {
            return .unavailable(RUBillingSafeErrors.checkoutNotEligible)
        }
        guard checkoutMethod == .sbp || checkoutMethod == .card else {
            return .unavailable(RUBillingSafeErrors.checkoutNotEligible)
        }
        guard let details = options.ruDetails,
              details.acceptsOfferAndPersonalDataProcessing,
              selection.product.kind != .autoRenewableSubscription
              || details.acceptsRecurringCharge,
              details.receiptEmail.map(Self.isValidEmail) != false
        else {
            return .unavailable(RUBillingSafeErrors.checkoutConsentRequired)
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
                acceptsAutoRenewal: details.acceptsRecurringCharge,
                customerEmail: details.receiptEmail
            ),
            selection: selection,
            remoteConfiguration: remoteConfiguration
        )
    }

    private static func isValidEmail(_ value: String) -> Bool {
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2,
              !parts[0].isEmpty,
              parts[1].contains("."),
              !parts[1].hasPrefix("."),
              !parts[1].hasSuffix(".")
        else {
            return false
        }
        return !value.contains(where: \.isWhitespace)
    }
}
