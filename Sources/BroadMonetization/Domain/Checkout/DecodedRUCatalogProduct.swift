struct DecodedRUCatalogProduct: Decodable {
    let catalogProductID: RUCatalogProductID
    let kind: RUCatalogProductKind
    let appStoreProductID: ProductID?
    let title: String?
    let price: Money?
    let displayPrice: String?
    let subscriptionPeriod: SubscriptionPeriod
    let supportedMethods: [CheckoutMethod]
    let credits: Int?
    let isSpecialOffer: Bool

    private enum CodingKeys: String, CodingKey {
        case catalogProductID
        case kind
        case appStoreProductID
        case title
        case price
        case displayPrice
        case subscriptionPeriod
        case supportedMethods
        case credits
        case isSpecialOffer
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        catalogProductID = try container.decode(
            RUCatalogProductID.self,
            forKey: .catalogProductID
        )
        kind = try container.decode(RUCatalogProductKind.self, forKey: .kind)
        appStoreProductID = try container.decodeIfPresent(
            ProductID.self,
            forKey: .appStoreProductID
        )
        title = try container.decodeIfPresent(String.self, forKey: .title)
        price = try container.decodeIfPresent(Money.self, forKey: .price)
        displayPrice = try container.decodeIfPresent(String.self, forKey: .displayPrice)
        subscriptionPeriod = try container.decode(
            SubscriptionPeriod.self,
            forKey: .subscriptionPeriod
        )
        supportedMethods = try container.decode(
            [CheckoutMethod].self,
            forKey: .supportedMethods
        )
        credits = try container.decodeIfPresent(Int.self, forKey: .credits)
        isSpecialOffer = try container.decodeIfPresent(
            Bool.self,
            forKey: .isSpecialOffer
        ) ?? false
    }
}
