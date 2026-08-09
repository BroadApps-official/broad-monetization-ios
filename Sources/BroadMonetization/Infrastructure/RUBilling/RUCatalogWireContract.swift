import Foundation

public protocol RUCatalogResponseDecoderProtocol: Sendable {
    func decodeCatalog(
        from data: Data,
        fetchedAt: Date
    ) throws -> RUCatalogPayload
}

/// Convenience decoder for the documented BroadApps platform contract.
/// A backend with a different schema supplies its own decoder without changing
/// Domain, repositories or UI.
public struct BroadAppsRUCatalogResponseDecoder: RUCatalogResponseDecoderProtocol {
    public init() {}

    public func decodeCatalog(
        from data: Data,
        fetchedAt: Date
    ) throws -> RUCatalogPayload {
        let response = try Self.makeDecoder().decode(BroadAppsRUCatalogResponseDTO.self, from: data)
        let products: [BroadAppsRUCatalogProductDTO] = switch response {
        case let .flat(items):
            items
        case let .partitioned(subscriptions, tokens, coupons):
            subscriptions.map { $0.with(kind: .subscription) }
                + tokens.map { $0.with(kind: .tokens) }
                + coupons.map { $0.with(kind: .coupon) }
        }

        return try RUCatalogPayload(
            products: products.map(makeDomainProduct),
            fetchedAt: fetchedAt
        )
    }
}

private extension BroadAppsRUCatalogResponseDecoder {
    func makeDomainProduct(_ product: BroadAppsRUCatalogProductDTO) throws -> RUCatalogProduct {
        let productID = try validatedIdentifier(product.productID)
        let appStoreProductID = try product.appStoreProductID.map(validatedIdentifier)
        let money = try product.price.map(makeMoney)
        var seenMethods = Set<CheckoutMethod>()
        let methods = product.paymentMethods.compactMap(makeCheckoutMethod).filter {
            seenMethods.insert($0).inserted
        }

        return try RUCatalogProduct(
            catalogProductID: RUCatalogProductID(rawValue: productID),
            kind: product.kind,
            appStoreProductID: appStoreProductID.map(ProductID.init(rawValue:)),
            price: money,
            displayPrice: product.displayPrice,
            subscriptionPeriod: makePeriod(product.subscriptionPeriod),
            supportedMethods: methods
        )
    }

    func makeMoney(_ price: BroadAppsRUPriceDTO) throws -> Money {
        guard !price.amount.isNaN, price.amount >= 0 else {
            throw BroadAppsRUCatalogWireError.invalidPrice
        }
        let code = price.currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.count == 3, code.allSatisfy({ $0.isASCII && $0.isLetter }) else {
            throw BroadAppsRUCatalogWireError.invalidPrice
        }
        return Money(amount: price.amount, currencyCode: code)
    }

    func makePeriod(_ period: BroadAppsRUPeriodDTO?) throws -> SubscriptionPeriod {
        guard let period else {
            return .unknown
        }
        let unit = period.unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let count = period.count, count > 0 else {
            throw BroadAppsRUCatalogWireError.invalidPeriod
        }

        switch unit {
        case "day":
            return .day(count)
        case "week":
            return .week(count)
        case "month":
            return .month(count)
        case "year":
            return .year(count)
        default:
            guard !unit.isEmpty else {
                throw BroadAppsRUCatalogWireError.invalidPeriod
            }
            return .custom(unit: unit, count: count)
        }
    }

    func makeCheckoutMethod(_ value: String) -> CheckoutMethod? {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "sbp":
            .sbp
        case "card":
            .card
        default:
            nil
        }
    }

    func validatedIdentifier(_ value: String) throws -> String {
        guard MonetizationIdentifierPolicy.isValid(value) else {
            throw BroadAppsRUCatalogWireError.invalidIdentifier
        }
        return value
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
