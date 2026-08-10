struct DecodedRUCatalogProduct: Decodable {
    let catalogProductID: RUCatalogProductID
    let kind: RUCatalogProductKind
    let appStoreProductID: ProductID?
    let price: Money?
    let displayPrice: String?
    let subscriptionPeriod: SubscriptionPeriod
    let supportedMethods: [CheckoutMethod]
}
