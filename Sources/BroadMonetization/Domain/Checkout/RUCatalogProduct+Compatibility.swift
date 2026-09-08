import Foundation

public extension RUCatalogProduct {
    /// Preserves the pre-1.4 initializer, including typed function references.
    init(
        catalogProductID: RUCatalogProductID,
        kind: RUCatalogProductKind,
        appStoreProductID: ProductID?,
        price: Money?,
        displayPrice: String?,
        subscriptionPeriod: SubscriptionPeriod,
        supportedMethods: [CheckoutMethod],
        title: String? = nil,
        credits: Int? = nil,
        isSpecialOffer: Bool = false
    ) {
        self.init(
            catalogProductID: catalogProductID,
            kind: kind,
            appStoreProductID: appStoreProductID,
            price: price,
            displayPrice: displayPrice,
            subscriptionPeriod: subscriptionPeriod,
            supportedMethods: supportedMethods,
            title: title,
            credits: credits,
            isSpecialOffer: isSpecialOffer,
            isDefault: false
        )
    }
}
