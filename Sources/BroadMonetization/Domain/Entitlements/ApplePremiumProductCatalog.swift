import Foundation

/// The complete entitlement catalog, including current and historical premium SKUs.
/// It is independent from the products rendered by a paywall.
public struct ApplePremiumProductCatalog: Sendable {
    public enum ProductKind: Equatable, Sendable {
        case autoRenewable
        case nonConsumable
        case nonRenewing(validFor: TimeInterval)
    }

    public struct Entry: Equatable, Sendable {
        public let productID: String
        public let kind: ProductKind

        public init(
            productID: String,
            kind: ProductKind
        ) {
            let trimmedProductID = productID.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            precondition(
                !trimmedProductID.isEmpty && trimmedProductID == productID,
                "Apple premium product ID must be nonempty and contain no surrounding whitespace"
            )
            if case let .nonRenewing(validFor) = kind {
                precondition(
                    validFor.isFinite && validFor > 0,
                    "Non-renewing entitlement duration must be finite and positive"
                )
            }

            self.productID = productID
            self.kind = kind
        }
    }

    public let entries: [Entry]

    private let entriesByProductID: [String: Entry]

    public init(entries: [Entry]) {
        precondition(
            !entries.isEmpty,
            "Apple premium product catalog must not be empty"
        )
        precondition(
            Set(entries.map(\.productID)).count == entries.count,
            "Apple premium product catalog must contain unique product IDs"
        )

        self.entries = entries
        entriesByProductID = Dictionary(
            uniqueKeysWithValues: entries.map { ($0.productID, $0) }
        )
    }

    public func entry(for productID: String) -> Entry? {
        entriesByProductID[productID]
    }
}
