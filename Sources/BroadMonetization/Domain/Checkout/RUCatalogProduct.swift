import Foundation

public struct RUCatalogProduct: Identifiable, Codable, Equatable, Sendable {
    public var id: RUCatalogProductID {
        catalogProductID
    }

    public let catalogProductID: RUCatalogProductID
    public let kind: RUCatalogProductKind
    public let appStoreProductID: ProductID?
    public let title: String?
    public let price: Money?
    public let displayPrice: String?
    public let subscriptionPeriod: SubscriptionPeriod
    public let supportedMethods: [CheckoutMethod]
    public let credits: Int?

    public init(
        catalogProductID: RUCatalogProductID,
        kind: RUCatalogProductKind,
        appStoreProductID: ProductID?,
        price: Money?,
        displayPrice: String?,
        subscriptionPeriod: SubscriptionPeriod,
        supportedMethods: [CheckoutMethod],
        title: String? = nil,
        credits: Int? = nil
    ) {
        precondition(
            Set(supportedMethods).count == supportedMethods.count,
            "RU catalog checkout methods must not contain duplicates"
        )
        precondition(
            !supportedMethods.contains(.apple),
            "Apple checkout is not an RU backend payment method"
        )
        precondition(
            credits.map { $0 >= 0 } != false,
            "RU catalog credits must be non-negative"
        )

        self.catalogProductID = catalogProductID
        self.kind = kind
        self.appStoreProductID = appStoreProductID
        self.title = title.catalogNonBlank
        self.price = price
        self.displayPrice = displayPrice.catalogNonBlank
        self.subscriptionPeriod = subscriptionPeriod
        self.supportedMethods = supportedMethods
        self.credits = credits
    }

    public init(from decoder: any Decoder) throws {
        let value = try DecodedRUCatalogProduct(from: decoder)

        guard MonetizationIdentifierPolicy.isValid(value.catalogProductID.rawValue),
              value.appStoreProductID.map({
                  MonetizationIdentifierPolicy.isValid($0.rawValue)
              }) ?? true,
              RUBillingPersistedValueValidator.isValid(value.price),
              RUBillingPersistedValueValidator.isValid(value.subscriptionPeriod),
              Set(value.supportedMethods).count == value.supportedMethods.count,
              !value.supportedMethods.contains(.apple),
              value.credits.map({ $0 >= 0 }) != false
        else {
            throw RUBillingPersistedValueValidator.decodingError(
                codingPath: decoder.codingPath,
                description: "Invalid persisted RU catalog product"
            )
        }

        self.init(
            catalogProductID: RUCatalogProductID(
                rawValue: value.catalogProductID.rawValue
            ),
            kind: value.kind,
            appStoreProductID: value.appStoreProductID.map {
                ProductID(rawValue: $0.rawValue)
            },
            price: value.price.map {
                Money(amount: $0.amount, currencyCode: $0.currencyCode)
            },
            displayPrice: value.displayPrice,
            subscriptionPeriod: SubscriptionPeriod(
                unit: value.subscriptionPeriod.unit,
                count: value.subscriptionPeriod.count
            ),
            supportedMethods: value.supportedMethods,
            title: value.title,
            credits: value.credits
        )
    }
}

private extension String? {
    var catalogNonBlank: String? {
        guard let value = self else {
            return nil
        }

        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
    }
}
