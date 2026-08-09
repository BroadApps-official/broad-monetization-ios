/// Explicit disabled adapters let a host compose Apple-only monetization without
/// fake endpoints, tokens or a permanently unresolved `.ruBilling` entitlement source.
public struct DisabledRUCatalogRepository: RUCatalogRepositoryProtocol {
    public init() {}

    public func loadCatalog() async -> RUCatalogLoadOutcome {
        .unavailable(RUBillingSafeErrors.notConfigured)
    }
}

struct DisabledRUPaymentStatusRepository: RUPaymentStatusRepositoryProtocol {
    func paymentStatus(
        for _: CheckoutSessionID
    ) async -> RUPaymentStatusOutcome {
        .unavailable(RUBillingSafeErrors.notConfigured)
    }
}

public struct DisabledRUSubscriptionRepository: RUSubscriptionRepositoryProtocol {
    public init() {}

    public func cancelSubscription(
        id _: RUSubscriptionID
    ) async -> RUSubscriptionCancellationOutcome {
        .unavailable(RUBillingSafeErrors.notConfigured)
    }
}
