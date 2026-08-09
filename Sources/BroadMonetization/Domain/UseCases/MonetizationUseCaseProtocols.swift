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
        remoteConfiguration: RemotePaywallConfiguration
    ) async -> CheckoutSelectedProductOutcome
}

public protocol RestorePurchasesUseCaseProtocol: Sendable {
    func callAsFunction() async -> RestoreOutcome
}

public protocol ResolveCheckoutMethodsUseCaseProtocol: Sendable {
    func callAsFunction(
        for product: MonetizationProduct,
        remoteConfiguration: RemotePaywallConfiguration
    ) async -> CheckoutMethodsResolution
}

protocol CreateRUCheckoutUseCaseProtocol: Sendable {
    func callAsFunction(
        _ request: RUCheckoutRequest
    ) async -> RUCheckoutCreationOutcome
}

/// Raw session polling is internal to `RUPaymentReturnCoordinator`, which first
/// proves that the durable record belongs to the current subject.
protocol RefreshRUPaymentUseCaseProtocol: Sendable {
    func callAsFunction(
        checkoutSessionID: CheckoutSessionID
    ) async -> RUPaymentRefreshOutcome
}

public protocol CancelRUSubscriptionUseCaseProtocol: Sendable {
    func callAsFunction(
        subscriptionID: RUSubscriptionID
    ) async -> RUSubscriptionCancellationOutcome
}

public protocol TrackPaywallEventUseCaseProtocol: Sendable {
    func callAsFunction(_ event: MonetizationAnalyticsEvent) async
}

public protocol ResolveSpecialOfferUseCaseProtocol: Sendable {
    /// Implementations must return `.unavailable(.notConfigured)` immediately for
    /// `nil` and must not touch placement, network, cache, timers or persistence.
    func callAsFunction(
        configuration: SpecialOfferConfiguration?
    ) async -> SpecialOfferResolution
}
