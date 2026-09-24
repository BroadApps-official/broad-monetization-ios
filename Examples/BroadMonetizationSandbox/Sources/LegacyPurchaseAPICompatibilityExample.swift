import BroadCore
import BroadMonetization

/// Compile-only proof that the 5.0 constructor and factory method remain
/// usable as function values after the optional catalog API was added.
enum LegacyPurchaseAPICompatibilityExample {
    typealias PurchaseInitializer = (
        any PurchaseRepositoryProtocol,
        any EntitlementRepositoryProtocol,
        any MonetizationAnalyticsProtocol,
        any PendingApplePurchaseStoreProtocol,
        MonetizationOperationGate,
        AppError,
        AppError?,
        AppError?
    ) -> PurchaseSelectedProductUseCase

    typealias ServiceFactory = (
        any EntitlementRepositoryProtocol,
        any MonetizationAnalyticsProtocol,
        (any PaywallCacheProtocol)?,
        MonetizationFlowErrors,
        any PendingApplePurchaseStoreProtocol,
        any PendingAppleTransactionRecoveryProtocol,
        MonetizationOperationGate,
        (any PaywallLoaderFactoryProtocol)?
    ) -> BroadMonetizationServices

    static let purchaseInitializer: PurchaseInitializer = PurchaseSelectedProductUseCase.init

    static func makeServices(_ factory: AdaptyMonetizationFactory) -> ServiceFactory {
        factory.makeServices
    }
}
