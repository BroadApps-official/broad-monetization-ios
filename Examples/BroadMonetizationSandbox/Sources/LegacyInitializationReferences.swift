import BroadMonetization
import Foundation

/// A compile-only consumer keeps the exact initializer function types used
/// before RU experiments were added. Default arguments alone cannot do this.
enum LegacyInitializationReferences {
    static func compileReferences() {
        let _: (
            AdaptyPlatformConfiguration, AdaptyPlacementRegistry,
            AdaptyMonetizationMessages, RemotePaywallConfigurationParser,
            LastValidRemoteConfigurationStore, AdaptyRepositoryContext
        ) -> AdaptyMonetizationFactory = AdaptyMonetizationFactory.init

        let _: (
            AdaptyPlatformConfiguration, any AdaptyIdentityProviderProtocol,
            AdaptyPlacementRegistry, AdaptyMonetizationMessages,
            RemotePaywallConfigurationParser, LastValidRemoteConfigurationStore,
            AdaptyRepositoryContext
        ) -> AdaptyMonetizationFactory = AdaptyMonetizationFactory.init

        let _: (
            RUCatalogProductID, RUCatalogProductKind, ProductID?, Money?, String?,
            SubscriptionPeriod, [CheckoutMethod], String?, Int?, Bool
        ) -> RUCatalogProduct = RUCatalogProduct.init

        let _: (
            Bool?, Bool?, PaywallAccessPolicy?, TimeInterval?,
            PaywallUIVariantID?, SpecialOfferRemoteConfiguration?
        ) -> RemotePaywallConfiguration = RemotePaywallConfiguration.init

        let _: (
            [String], [String], [String], [String], [String], [String], [String],
            [String], [String], [String], [String], [String], [String]
        ) -> RemoteConfigKeyRegistry = RemoteConfigKeyRegistry.init
    }
}
