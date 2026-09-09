import CryptoKit
import Foundation

enum RUFallbackProductIdentity {
    static let prefix = "ru-fallback-row-"

    static func fingerprint(_ row: RUCatalogProduct) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(row) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func products(
        in catalog: RUCatalogPayload, selectedRows: [RUCatalogProduct]? = nil
    ) -> [MonetizationProduct] {
        catalog.products.enumerated().compactMap { index, row in
            // Keep the index in the original catalog, including skipped rows.
            // Re-indexing a default subset would bind checkout to another row.
            guard !row.isSpecialOffer, selectedRows?.contains(row) ?? true else { return nil }
            return MonetizationProduct(
                presentationID: .generated(),
                reference: ProductReference(rawValue: "\(prefix)\(index)"),
                productID: ProductID(rawValue: row.catalogProductID.rawValue),
                commercialFingerprint: fingerprint(row),
                kind: productKind(for: row),
                title: row.title,
                price: row.price,
                displayPrice: row.displayPrice,
                subscriptionPeriod: row.subscriptionPeriod,
                catalogSource: .ruBackend
            )
        }
    }

    private static func productKind(for row: RUCatalogProduct) -> MonetizationProductKind {
        guard row.kind == .subscription else { return .unknown }
        switch row.subscriptionPeriod.unit {
        case .day, .week, .month, .year: return .autoRenewableSubscription
        case .custom, .unknown: return .unknown
        }
    }

    static func match(_ product: MonetizationProduct, in catalog: RUCatalogPayload) -> RUCatalogProduct? {
        guard product.catalogSource == .ruBackend,
              product.reference.rawValue.hasPrefix(prefix),
              let index = Int(product.reference.rawValue.dropFirst(prefix.count)),
              catalog.products.indices.contains(index),
              let expected = product.commercialFingerprint
        else { return nil }
        let row = catalog.products[index]
        guard !row.isSpecialOffer, row.kind == .subscription,
              row.catalogProductID.rawValue == product.productID.rawValue,
              fingerprint(row) == expected,
              product.price == row.price,
              product.subscriptionPeriod == row.subscriptionPeriod
        else { return nil }
        return row
    }
}
