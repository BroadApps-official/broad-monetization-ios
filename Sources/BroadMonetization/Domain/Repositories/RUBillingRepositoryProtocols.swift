/// RU billing is intentionally split into focused boundaries. There is no giant
/// `RUBillingRepositoryProtocol`: catalog, checkout, polling and cancellation have
/// different availability, caching, retry and authorization semantics.
public protocol RUCatalogRepositoryProtocol: Sendable {
    func loadCatalog() async -> RUCatalogLoadOutcome
}

/// Raw backend-session creation stays module-internal so callers cannot bypass
/// storefront, remote-gate, catalog-matching and durable-pending boundaries.
protocol RUCheckoutRepositoryProtocol: Sendable {
    func createCheckout(
        _ request: RUCheckoutRequest
    ) async -> RUCheckoutCreationOutcome
}

/// Raw payment-session polling remains module-internal. Public callers resume
/// through the subject-checking `RUPaymentReturnCoordinator` instead.
protocol RUPaymentStatusRepositoryProtocol: Sendable {
    func paymentStatus(
        for checkoutSessionID: CheckoutSessionID
    ) async -> RUPaymentStatusOutcome
}

public protocol RUSubscriptionRepositoryProtocol: Sendable {
    func cancelSubscription(
        id: RUSubscriptionID
    ) async -> RUSubscriptionCancellationOutcome
}
