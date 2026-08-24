import BroadCore

public struct ResolveCheckoutMethodsUseCase: ResolveCheckoutMethodsUseCaseProtocol {
    private let storefrontRepository: any StorefrontRepositoryProtocol
    private let catalogRepository: any RUCatalogRepositoryProtocol
    private let productMatcher: RUCatalogProductMatcher
    private let gate: RUBillingGate
    private let logger: any BroadLoggerProtocol

    public init(
        storefrontRepository: any StorefrontRepositoryProtocol,
        catalogRepository: any RUCatalogRepositoryProtocol,
        productMatcher: RUCatalogProductMatcher = RUCatalogProductMatcher(),
        isFeatureEnabled: Bool,
        deviceContextProvider: any RUBillingDeviceContextProviderProtocol =
            SystemRUBillingDeviceContextProvider(),
        debugOverrideStore: RUBillingDebugOverrideStore = RUBillingDebugOverrideStore(),
        logger: any BroadLoggerProtocol = NoOpBroadLogger()
    ) {
        self.storefrontRepository = storefrontRepository
        self.catalogRepository = catalogRepository
        self.productMatcher = productMatcher
        gate = RUBillingGate(
            isFeatureEnabled: isFeatureEnabled,
            deviceContextProvider: deviceContextProvider,
            debugOverrideStore: debugOverrideStore
        )
        self.logger = logger
    }

    public func callAsFunction(
        for product: MonetizationProduct,
        remoteConfiguration: RemotePaywallConfiguration
    ) async -> CheckoutMethodsResolution {
        guard product.isEligibleForGenericPurchase else {
            return resolution(
                methods: [],
                storefront: nil,
                reason: .productNotEligible
            )
        }

        var methods: [CheckoutMethod] = product.catalogSource == .ruBackend ? [] : [.apple]

        let gateReason = gate.availabilityReason(
            remoteConfiguration: remoteConfiguration
        )
        guard gateReason.allowsRUBilling else {
            return resolution(
                methods: methods,
                storefront: nil,
                reason: gateReason
            )
        }
        let storefront: Storefront? = switch await storefrontRepository.currentStorefront() {
        case let .available(value): value
        case .unavailable: nil
        }
        guard case let .loaded(catalog) = await catalogRepository.loadCatalog() else {
            return resolution(
                methods: methods,
                storefront: storefront,
                reason: .catalogUnavailable
            )
        }
        guard let matched = productMatcher.matchPremiumEntitlementProduct(
            product,
            in: catalog
        ) else {
            return resolution(
                methods: methods,
                storefront: storefront,
                reason: .productNotMatched
            )
        }

        for method in matched.supportedMethods where !methods.contains(method) {
            methods.append(method)
        }
        let hasRUCheckoutMethod = methods.contains(.sbp) || methods.contains(.card)
        return resolution(
            methods: methods,
            storefront: storefront,
            reason: hasRUCheckoutMethod ? gateReason : .methodsUnavailable
        )
    }
}

private extension ResolveCheckoutMethodsUseCase {
    func resolution(
        methods: [CheckoutMethod],
        storefront: Storefront?,
        reason: RUBillingAvailabilityReason
    ) -> CheckoutMethodsResolution {
        logger.log(
            .ruBillingAvailabilityEvaluated(
                reason: reason.logValue,
                methodCount: methods.count
            )
        )
        return CheckoutMethodsResolution(
            methods: methods,
            storefront: storefront,
            ruBillingAvailability: reason
        )
    }
}

private extension RUBillingAvailabilityReason {
    var logValue: BroadLogRUBillingAvailabilityReason {
        switch self {
        case .available: .available
        case .productNotEligible: .productNotEligible
        case .hostDisabled: .hostDisabled
        case .debugForcedEnabled: .debugForcedEnabled
        case .debugForcedDisabled: .debugForcedDisabled
        case .remoteFlagAbsent: .remoteFlagAbsent
        case .remoteFlagDisabled: .remoteFlagDisabled
        case .remoteFlagInvalid: .remoteFlagInvalid
        case .unqualifiedRemoteConfiguration: .unqualifiedRemoteConfiguration
        case .deviceContextNotRussian: .deviceContextNotRussian
        case .catalogUnavailable: .catalogUnavailable
        case .productNotMatched: .productNotMatched
        case .methodsUnavailable: .methodsUnavailable
        }
    }
}
