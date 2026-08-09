import Adapty
import CryptoKit
import Foundation

extension AdaptyPaywallRepository {
    static func mapProducts(
        _ products: [any AdaptyPaywallProduct]
    ) -> [MonetizationProduct] {
        products.map { product in
            let fingerprint = commercialFingerprint(product)
            let hasValidatedVendorProductID = MonetizationIdentifierPolicy.isValid(
                product.vendorProductId
            )

            return MonetizationProduct(
                presentationID: .generated(),
                reference: .generatedForAdapty(),
                productID: productID(
                    for: product,
                    commercialFingerprint: fingerprint
                ),
                commercialFingerprint: fingerprint,
                kind: productKind(product),
                title: product.localizedTitle,
                subtitle: nil,
                // A malformed provider SKU remains visible in its original
                // position, but can never authorize either Apple or RU checkout.
                price: hasValidatedVendorProductID ? money(product) : nil,
                displayPrice: displayPrice(product),
                subscriptionPeriod: subscriptionPeriod(product),
                catalogSource: .adapty
            )
        }
    }

    static func productID(
        for product: any AdaptyPaywallProduct,
        commercialFingerprint: String
    ) -> ProductID {
        guard MonetizationIdentifierPolicy.isValid(product.vendorProductId) else {
            // Never trim, expose or otherwise reinterpret malformed provider data.
            // The fixed prefix plus SHA-256 fingerprint is deterministic, bounded
            // and valid for domain storage while ProductPresentationID remains the
            // identity of this exact UI occurrence.
            return ProductID(
                rawValue: "adapty-opaque-unavailable-\(commercialFingerprint)"
            )
        }

        return ProductID(rawValue: product.vendorProductId)
    }

    static func productKind(
        _ product: any AdaptyPaywallProduct
    ) -> MonetizationProductKind {
        if product.subscriptionPeriod != nil {
            return .autoRenewableSubscription
        }

        switch product.adaptyProductType
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() {
        case "consumable":
            return .consumable
        case "non_consumable", "non-consumable", "lifetime":
            return .nonConsumable
        case "non_renewing_subscription", "non-renewing-subscription":
            return .nonRenewingSubscription
        default:
            return .unknown
        }
    }

    static func commercialFingerprint(
        _ product: any AdaptyPaywallProduct
    ) -> String {
        var fields: [String?] = [
            product.adaptyProductId,
            product.vendorProductId,
            product.variationId,
            String(product.paywallProductIndex),
            product.accessLevelId,
            product.adaptyProductType,
            decimalString(product.price),
            product.currencyCode,
            product.subscriptionGroupIdentifier,
            product.subscriptionPeriod.map(periodString)
        ]

        if let offer = product.subscriptionOffer {
            fields.append(contentsOf: [
                offer.identifier,
                offer.offerType.rawValue,
                periodString(offer.subscriptionPeriod),
                String(offer.numberOfPeriods),
                String(offer.paymentMode.rawValue),
                decimalString(offer.price),
                offer.currencyCode
            ])
        } else {
            fields.append(nil)
        }

        let canonical = fields.map { field in
            guard let field else {
                return "-"
            }
            return "\(field.utf8.count):\(field)"
        }.joined(separator: "|")
        return SHA256.hash(data: Data(canonical.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static func periodString(_ period: AdaptySubscriptionPeriod) -> String {
        "\(period.unit.description):\(period.numberOfUnits)"
    }

    static func decimalString(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    static func money(
        _ product: any AdaptyPaywallProduct
    ) -> Money? {
        guard !product.price.isNaN,
              product.price >= 0,
              let currencyCode = product.currencyCode,
              currencyCode.count == 3,
              currencyCode.allSatisfy({ character in
                  character.isASCII && character.isLetter
              })
        else {
            return nil
        }
        return Money(amount: product.price, currencyCode: currencyCode)
    }

    static func displayPrice(
        _ product: any AdaptyPaywallProduct
    ) -> String? {
        if let localizedPrice = product.localizedPrice,
           !localizedPrice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return localizedPrice
        }

        guard !product.price.isNaN, product.price >= 0 else {
            return nil
        }

        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = product.priceLocale
        formatter.currencyCode = product.currencyCode
        return formatter.string(from: NSDecimalNumber(decimal: product.price))
    }

    static func subscriptionPeriod(
        _ product: any AdaptyPaywallProduct
    ) -> SubscriptionPeriod {
        guard let period = product.subscriptionPeriod, period.numberOfUnits > 0 else {
            return .unknown
        }

        switch period.unit {
        case .day: return .day(period.numberOfUnits)
        case .week: return .week(period.numberOfUnits)
        case .month: return .month(period.numberOfUnits)
        case .year: return .year(period.numberOfUnits)
        case .unknown:
            return SubscriptionPeriod(unit: .unknown, count: period.numberOfUnits)
        }
    }
}

private extension ProductReference {
    static func generatedForAdapty() -> ProductReference {
        ProductReference(rawValue: "adapty-\(UUID().uuidString.lowercased())")
    }
}
