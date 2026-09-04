import Foundation

enum BroadAppsRUCatalogResponseDTO: Decodable {
    case flat([BroadAppsRUCatalogProductDTO])
    case partitioned(
        subscriptions: [BroadAppsRUCatalogProductDTO],
        tokens: [BroadAppsRUCatalogProductDTO],
        coupons: [BroadAppsRUCatalogProductDTO]
    )

    init(from decoder: Decoder) throws {
        if let products = try? decoder.singleValueContainer().decode([BroadAppsRUCatalogProductDTO].self) {
            self = .flat(products)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let products = try container.decodeIfPresent([BroadAppsRUCatalogProductDTO].self, forKey: .products) {
            self = .flat(products)
            return
        }

        self = try .partitioned(
            subscriptions: container.decodeIfPresent([BroadAppsRUCatalogProductDTO].self, forKey: .subscriptions) ?? [],
            tokens: container.decodeIfPresent([BroadAppsRUCatalogProductDTO].self, forKey: .tokens) ?? [],
            coupons: container.decodeIfPresent([BroadAppsRUCatalogProductDTO].self, forKey: .coupons) ?? []
        )
    }

    enum CodingKeys: String, CodingKey {
        case products
        case subscriptions
        case tokens
        case coupons
    }
}

struct BroadAppsRUCatalogProductDTO: Decodable {
    let productID: String
    let kind: RUCatalogProductKind
    let appStoreProductID: String?
    let price: BroadAppsRUPriceDTO?
    let displayPrice: String?
    let subscriptionPeriod: BroadAppsRUPeriodDTO?
    let paymentMethods: [String]
    let isSpecialOffer: Bool

    init(
        productID: String,
        kind: RUCatalogProductKind,
        appStoreProductID: String?,
        price: BroadAppsRUPriceDTO?,
        displayPrice: String?,
        subscriptionPeriod: BroadAppsRUPeriodDTO?,
        paymentMethods: [String],
        isSpecialOffer: Bool
    ) {
        self.productID = productID
        self.kind = kind
        self.appStoreProductID = appStoreProductID
        self.price = price
        self.displayPrice = displayPrice
        self.subscriptionPeriod = subscriptionPeriod
        self.paymentMethods = paymentMethods
        self.isSpecialOffer = isSpecialOffer
    }

    func with(kind: RUCatalogProductKind) -> BroadAppsRUCatalogProductDTO {
        BroadAppsRUCatalogProductDTO(
            productID: productID,
            kind: kind,
            appStoreProductID: appStoreProductID,
            price: price,
            displayPrice: displayPrice,
            subscriptionPeriod: subscriptionPeriod,
            paymentMethods: paymentMethods,
            isSpecialOffer: isSpecialOffer
        )
    }

    enum CodingKeys: String, CodingKey {
        case productID = "product_id"
        case kind
        case appStoreProductID = "app_store_product_id"
        case price
        case displayPrice = "display_price"
        case subscriptionPeriod = "subscription_period"
        case paymentMethods = "payment_methods"
        case isSpecialOfferCamel = "isSpecialOffer"
        case isSpecialOfferSnake = "is_special_offer"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        productID = try container.decode(String.self, forKey: .productID)
        kind = try container.decodeIfPresent(RUCatalogProductKind.self, forKey: .kind) ?? .unknown
        appStoreProductID = try container.decodeIfPresent(String.self, forKey: .appStoreProductID)
        price = try container.decodeIfPresent(BroadAppsRUPriceDTO.self, forKey: .price)
        displayPrice = try container.decodeIfPresent(String.self, forKey: .displayPrice)
        subscriptionPeriod = try container.decodeIfPresent(BroadAppsRUPeriodDTO.self, forKey: .subscriptionPeriod)
        paymentMethods = try container.decodeIfPresent([String].self, forKey: .paymentMethods) ?? []
        isSpecialOffer = try container.decodeIfPresent(
            Bool.self,
            forKey: .isSpecialOfferCamel
        ) ?? container.decodeIfPresent(Bool.self, forKey: .isSpecialOfferSnake) ?? false
    }
}

struct BroadAppsRUPriceDTO: Decodable {
    let amount: Decimal
    let currencyCode: String

    enum CodingKeys: String, CodingKey {
        case amount
        case currencyCode = "currency_code"
    }
}

struct BroadAppsRUPeriodDTO: Decodable {
    let unit: String
    let count: Int?
}

enum BroadAppsRUCatalogWireError: Error {
    case invalidIdentifier
    case invalidPrice
    case invalidPeriod
}
