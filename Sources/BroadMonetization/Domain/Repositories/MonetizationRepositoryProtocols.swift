public protocol MonetizationRepositoryProtocol: Sendable {
    func activate() async -> MonetizationActivationOutcome
}

/// Loads exactly the requested logical placement. Cache and `.main` fallback policy
/// belong to the load-paywall use case so the resulting origin remains observable.
public protocol PaywallRepositoryProtocol: Sendable {
    func loadPaywall(for placementID: PlacementID) async -> PaywallLoadOutcome
}

public protocol PurchaseRepositoryProtocol: Sendable {
    func purchase(_ request: PurchaseRequest) async -> PurchaseAttemptOutcome
}

public protocol RestoreRepositoryProtocol: Sendable {
    func restorePurchases() async -> RestoreAttemptOutcome
}

public protocol RemoteConfigRepositoryProtocol: Sendable {
    func configuration(
        for paywallReference: PaywallReference
    ) async -> RemoteConfigurationLoadOutcome
}

public protocol StorefrontRepositoryProtocol: Sendable {
    /// Informational App Store metadata. It does not authorize RU billing.
    func currentStorefront() async -> StorefrontResolution
}

/// A live StoreKit value for consumers that need current storefront metadata.
public protocol LiveStorefrontRepositoryProtocol: Sendable {
    func liveCurrentStorefront() async -> StorefrontResolution
}

/// A non-authoritative value suitable for explanatory UI only.
public protocol StorefrontHintRepositoryProtocol: Sendable {
    func cachedStorefrontHint() async -> StorefrontResolution
}

public protocol PaywallCacheProtocol: Sendable {
    func readPaywall(for placementID: PlacementID) async -> PaywallCacheReadOutcome
    func writePaywall(_ paywall: PaywallPayload, for placementID: PlacementID) async -> PaywallCacheWriteOutcome
}

public protocol MonetizationAnalyticsProtocol: Sendable {
    func track(_ event: MonetizationAnalyticsEvent) async
}

public enum SpecialOfferStateLoadOutcome: Equatable, Sendable {
    case loaded(SpecialOfferState)
    case unavailable
}

public protocol SpecialOfferStateRepositoryProtocol: Sendable {
    func state(
        for configuration: SpecialOfferConfiguration
    ) async -> SpecialOfferStateLoadOutcome

    @discardableResult
    func save(
        _ state: SpecialOfferState,
        for configuration: SpecialOfferConfiguration
    ) async -> Bool
}
