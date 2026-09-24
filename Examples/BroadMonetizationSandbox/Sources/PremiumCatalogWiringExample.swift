import BroadMonetization

/// Compile-only wiring: use the same catalog for StoreKit entitlement and
/// purchase preflight, so a remote paywall cannot sell an unrecognized SKU.
enum PremiumCatalogWiringExample {
    static func makeServices(
        factory: AdaptyMonetizationFactory,
        entitlementRepository: any EntitlementRepositoryProtocol,
        analytics: any MonetizationAnalyticsProtocol,
        errors: MonetizationFlowErrors,
        pendingStore: any PendingApplePurchaseStoreProtocol,
        transactionRecovery: any PendingAppleTransactionRecoveryProtocol,
        operationGate: MonetizationOperationGate,
        premiumCatalog: ApplePremiumProductCatalog
    ) -> BroadMonetizationServices {
        factory.makeServices(
            entitlementRepository: entitlementRepository,
            analytics: analytics,
            errors: errors,
            pendingApplePurchaseStore: pendingStore,
            pendingAppleTransactionRecovery: transactionRecovery,
            operationGate: operationGate,
            premiumProductCatalog: premiumCatalog
        )
    }
}
