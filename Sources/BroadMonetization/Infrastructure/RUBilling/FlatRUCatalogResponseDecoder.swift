import Foundation

/// Decodes the flat catalog currently used by BroadApps backends:
/// `{ "products": [{ "productId", "kind", "price", "currency" }] }`.
///
/// `price` is interpreted as a major currency-unit amount. A backend that sends
/// minor units or a different envelope must provide its own decoder.
public struct FlatRUCatalogResponseDecoder: RUCatalogResponseDecoderProtocol {
    private let supportedMethods: [CheckoutMethod]

    /// Payment methods are explicit host configuration because the flat
    /// catalog does not always return them. The decoder never invents card or
    /// SBP availability.
    public init(supportedMethods: [CheckoutMethod]) {
        precondition(
            Set(supportedMethods).count == supportedMethods.count,
            "Flat RU catalog methods must not contain duplicates"
        )
        precondition(
            supportedMethods.allSatisfy { $0 == .sbp || $0 == .card },
            "Flat RU catalog supports only SBP or card backend methods"
        )
        self.supportedMethods = supportedMethods
    }

    public func decodeCatalog(
        from data: Data,
        fetchedAt: Date
    ) throws -> RUCatalogPayload {
        let response = try JSONDecoder().decode(FlatRUCatalogResponse.self, from: data)
        return try RUCatalogPayload(
            products: response.products.map(makeDomainProduct),
            fetchedAt: fetchedAt
        )
    }
}

private extension FlatRUCatalogResponseDecoder {
    func makeDomainProduct(_ product: FlatRUCatalogProduct) throws -> RUCatalogProduct {
        let productID = try validatedIdentifier(product.productID)
        let appStoreProductID = try product.appStoreProductID.map(validatedIdentifier)
        let money = try makeMoney(amount: product.price, currency: product.currency)
        let methods = try makeMethods(product.paymentMethods)
        guard product.credits.map({ $0 >= 0 }) != false else {
            throw FlatRUCatalogWireError.invalidCredits
        }

        return RUCatalogProduct(
            catalogProductID: RUCatalogProductID(rawValue: productID),
            kind: makeKind(product.kind),
            appStoreProductID: appStoreProductID.map(ProductID.init(rawValue:)),
            price: money,
            displayPrice: product.displayPrice ?? money.flatMap(RUBPriceFormatter().string),
            subscriptionPeriod: makePeriod(product.period),
            supportedMethods: methods,
            title: product.title,
            credits: product.credits
        )
    }

    func makeMoney(amount: Decimal?, currency: String?) throws -> Money? {
        guard let amount else {
            return nil
        }
        guard !amount.isNaN, amount >= 0,
              let currency,
              currency.trimmingCharacters(in: .whitespacesAndNewlines).count == 3
        else {
            throw FlatRUCatalogWireError.invalidPrice
        }
        let code = currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.allSatisfy({ $0.isASCII && $0.isLetter }) else {
            throw FlatRUCatalogWireError.invalidPrice
        }
        return Money(amount: amount, currencyCode: code)
    }

    func makeMethods(_ values: [String]?) throws -> [CheckoutMethod] {
        guard let values else {
            return supportedMethods
        }
        var seen = Set<CheckoutMethod>()
        return try values.map { value in
            let method: CheckoutMethod = switch value
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() {
            case "sbp": .sbp
            case "card": .card
            default: throw FlatRUCatalogWireError.invalidPaymentMethod
            }
            guard seen.insert(method).inserted else {
                throw FlatRUCatalogWireError.invalidPaymentMethod
            }
            return method
        }
    }

    func makeKind(_ value: String?) -> RUCatalogProductKind {
        switch value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "subscription": .subscription
        case "token", "tokens": .tokens
        case "coupon": .coupon
        default: .unknown
        }
    }

    func makePeriod(_ value: String?) -> SubscriptionPeriod {
        guard let value else {
            return .unknown
        }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "day", "daily": return .day(1)
        case "week", "weekly": return .week(1)
        case "month", "monthly": return .month(1)
        case "year", "yearly", "annual": return .year(1)
        case "": return .unknown
        default: return .custom(unit: normalized, count: 1)
        }
    }

    func validatedIdentifier(_ value: String) throws -> String {
        guard MonetizationIdentifierPolicy.isValid(value) else {
            throw FlatRUCatalogWireError.invalidIdentifier
        }
        return value
    }
}

private struct FlatRUCatalogResponse: Decodable {
    let products: [FlatRUCatalogProduct]
}

private struct FlatRUCatalogProduct: Decodable {
    let productID: String
    let appStoreProductID: String?
    let title: String?
    let kind: String?
    let period: String?
    let price: Decimal?
    let currency: String?
    let credits: Int?
    let displayPrice: String?
    let paymentMethods: [String]?

    private enum CodingKeys: String, CodingKey {
        case productIDCamel = "productId"
        case productIDSnake = "product_id"
        case appStoreProductIDCamel = "appStoreProductId"
        case appStoreProductIDSnake = "app_store_product_id"
        case title
        case kind
        case period
        case price
        case currency
        case credits
        case displayPriceCamel = "displayPrice"
        case displayPriceSnake = "display_price"
        case paymentMethodsCamel = "paymentMethods"
        case paymentMethodsSnake = "payment_methods"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let productID = try container.decodeIfPresent(String.self, forKey: .productIDCamel)
            ?? container.decodeIfPresent(String.self, forKey: .productIDSnake)
        else {
            throw FlatRUCatalogWireError.invalidIdentifier
        }
        self.productID = productID
        appStoreProductID = try container.decodeIfPresent(String.self, forKey: .appStoreProductIDCamel)
            ?? container.decodeIfPresent(String.self, forKey: .appStoreProductIDSnake)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        kind = try container.decodeIfPresent(String.self, forKey: .kind)
        period = try container.decodeIfPresent(String.self, forKey: .period)
        price = try container.decodeIfPresent(Decimal.self, forKey: .price)
        currency = try container.decodeIfPresent(String.self, forKey: .currency)
        credits = try container.decodeIfPresent(Int.self, forKey: .credits)
        displayPrice = try container.decodeIfPresent(String.self, forKey: .displayPriceCamel)
            ?? container.decodeIfPresent(String.self, forKey: .displayPriceSnake)
        paymentMethods = try container.decodeIfPresent([String].self, forKey: .paymentMethodsCamel)
            ?? container.decodeIfPresent([String].self, forKey: .paymentMethodsSnake)
    }
}

private enum FlatRUCatalogWireError: Error {
    case invalidCredits
    case invalidIdentifier
    case invalidPrice
    case invalidPaymentMethod
}
