public protocol ActivateMonetizationUseCaseProtocol: Sendable {
    func callAsFunction() async -> MonetizationActivationOutcome
}

public protocol LoadPaywallUseCaseProtocol: Sendable {
    func callAsFunction(
        _ request: PaywallLoadRequest
    ) async -> PaywallLoadOutcome
}

public protocol SelectProductUseCaseProtocol: Sendable {
    func callAsFunction(
        productPresentationID: ProductPresentationID,
        in paywall: PaywallPayload
    ) -> ProductSelection?
}

public protocol PurchaseSelectedProductUseCaseProtocol: Sendable {
    func callAsFunction(
        _ selection: ProductSelection,
        using checkoutMethod: CheckoutMethod
    ) async -> PurchaseOutcome
}

public protocol CheckoutSelectedProductUseCaseProtocol: Sendable {
    func callAsFunction(
        _ selection: ProductSelection,
        using checkoutMethod: CheckoutMethod,
        remoteConfiguration: RemotePaywallConfiguration,
        options: CheckoutOptions
    ) async -> CheckoutSelectedProductOutcome
}

public extension CheckoutSelectedProductUseCaseProtocol {
    func callAsFunction(
        _ selection: ProductSelection,
        using checkoutMethod: CheckoutMethod,
        remoteConfiguration: RemotePaywallConfiguration
    ) async -> CheckoutSelectedProductOutcome {
        await callAsFunction(
            selection,
            using: checkoutMethod,
            remoteConfiguration: remoteConfiguration,
            options: .standard
        )
    }
}

public protocol RestorePurchasesUseCaseProtocol: Sendable {
    func callAsFunction() async -> RestoreOutcome
}

public protocol ResolveCheckoutMethodsUseCaseProtocol: Sendable {
    func callAsFunction(
        for product: MonetizationProduct,
        remoteConfiguration: RemotePaywallConfiguration
    ) async -> CheckoutMethodsResolution

    func callAsFunction(
        for selection: ProductSelection,
        remoteConfiguration: RemotePaywallConfiguration
    ) async -> CheckoutMethodsResolution
}

public extension ResolveCheckoutMethodsUseCaseProtocol {
    func callAsFunction(
        for selection: ProductSelection,
        remoteConfiguration: RemotePaywallConfiguration
    ) async -> CheckoutMethodsResolution {
        await callAsFunction(
            for: selection.product,
            remoteConfiguration: remoteConfiguration
        )
    }
}

public protocol TrackPaywallEventUseCaseProtocol: Sendable {
    func callAsFunction(_ event: MonetizationAnalyticsEvent) async
}

public protocol ResolveSpecialOfferUseCaseProtocol: Sendable {
    /// Loads the gate and offer while the ordinary paywall is visible. This does
    /// not start or change the persisted Special Offer window.
    func prepare(configuration: SpecialOfferConfiguration) async

    /// Implementations must return `.unavailable(.notConfigured)` immediately for
    /// `nil` and must not touch placement, network, cache, timers or persistence.
    func callAsFunction(
        configuration: SpecialOfferConfiguration?
    ) async -> SpecialOfferResolution

    /// Clears the persisted window after a confirmed purchase or restore.
    @discardableResult
    func resetCycle(
        configuration: SpecialOfferConfiguration
    ) async -> Bool
}

public extension ResolveSpecialOfferUseCaseProtocol {
    /// Keeps existing custom resolvers source compatible.
    func prepare(configuration _: SpecialOfferConfiguration) async {}

    /// Source-compatible default for custom resolvers. Production resolvers
    /// should persist the reset and return `true` only after it succeeds.
    @discardableResult
    func resetCycle(
        configuration _: SpecialOfferConfiguration
    ) async -> Bool {
        false
    }
}
