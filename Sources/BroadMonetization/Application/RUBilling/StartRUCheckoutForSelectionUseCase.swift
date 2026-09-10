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
    private let usesAccountPolicy: Bool
    private let tokenOnly: Bool

    private var isStarting = false

    init(
        catalogRepository: any RUCatalogRepositoryProtocol,
        matcher: RUCatalogProductMatcher = RUCatalogProductMatcher(),
        checkoutFlow: RUCheckoutFlowCoordinator,
        usesAccountPolicy: Bool = false,
        tokenOnly: Bool = false
    ) {
        self.catalogRepository = catalogRepository
        self.matcher = matcher
        self.checkoutFlow = checkoutFlow
        self.usesAccountPolicy = usesAccountPolicy
        self.tokenOnly = tokenOnly
    }

    func callAsFunction(
        _ selection: ProductSelection,
        using checkoutMethod: CheckoutMethod,
        remoteConfiguration: RemotePaywallConfiguration,
        options: CheckoutOptions
    ) async -> RUCheckoutFlowOutcome {
        let eligible = tokenOnly
            ? usesAccountPolicy && selection.product.kind == .consumable && selection.product.price != nil
            && selection.requestedPlacementID != .specialOffer
            : selection.product.isEligibleForGenericPurchase
        guard eligible else {
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

        guard let matchedProduct = await matchedProduct(for: selection),
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
            remoteConfiguration: remoteConfiguration,
            accountExpectation: usesAccountPolicy ? RUAccountCheckoutExpectation(
                kind: tokenOnly ? .tokens : .subscription,
                subscriptionPeriod: matchedProduct.subscriptionPeriod
            ) : nil
        )
    }

    private func matchedProduct(for selection: ProductSelection) async -> RUCatalogProduct? {
        let outcome: RUCatalogLoadOutcome = if selection.product.catalogSource == .ruBackend,
                                               selection.product.reference.rawValue.hasPrefix(RUFallbackProductIdentity.prefix) {
            if let fresh = catalogRepository as? any FreshRUCatalogRepositoryProtocol {
                await fresh.loadFreshCatalog()
            } else {
                .unavailable(RUBillingSafeErrors.catalogUnavailable)
            }
        } else {
            await catalogRepository.loadCatalog()
        }
        guard !Task.isCancelled, case let .loaded(catalog) = outcome else { return nil }
        if tokenOnly {
            return matcher.match(product: selection.product, kind: .tokens, in: catalog)
        }
        return selection.requestedPlacementID == .specialOffer
            ? matcher.matchSpecialOfferProduct(selection.product, in: catalog)
            : matcher.matchPremiumEntitlementProduct(selection.product, in: catalog)
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
