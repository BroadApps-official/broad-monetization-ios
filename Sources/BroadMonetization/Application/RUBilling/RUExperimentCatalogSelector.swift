public enum RUExperimentCatalogKind: Equatable, Sendable {
    case subscriptions
    case tokens
    case specialOffer
}

public enum RUExperimentCatalogSelectionSource: Equatable, Sendable {
    case placementMatches
    case defaultProducts
    case completeSection
}

/// An explicit display selection; the original backend payload is unchanged.
public struct RUExperimentCatalogSelection: Equatable, Sendable {
    public let products: [RUCatalogProduct]
    public let source: RUExperimentCatalogSelectionSource
    public let missingProductIDs: [ProductID]
}

/// Opt-in RU variant selection. It never changes an Adapty product array or
/// invents a raw SDK product. Backend order and repeated rows are preserved.
public struct RUExperimentCatalogSelector: Sendable {
    public init() {}

    public func select(
        productIDs: [ProductID],
        in catalog: RUCatalogPayload,
        kind: RUExperimentCatalogKind
    ) -> RUExperimentCatalogSelection {
        let candidates = catalog.products.filter { belongs($0, to: kind) }
        let matched = candidates.filter { product in
            productIDs.contains { matches($0, product: product) }
        }
        let missing = productIDs.filter { identifier in
            !candidates.contains { matches(identifier, product: $0) }
        }
        if !matched.isEmpty {
            return RUExperimentCatalogSelection(
                products: matched, source: .placementMatches, missingProductIDs: missing
            )
        }
        let defaults = candidates.filter(\.isDefault)
        return RUExperimentCatalogSelection(
            products: defaults.isEmpty ? candidates : defaults,
            source: defaults.isEmpty ? .completeSection : .defaultProducts,
            missingProductIDs: missing
        )
    }

    private func belongs(_ product: RUCatalogProduct, to kind: RUExperimentCatalogKind) -> Bool {
        switch kind {
        case .subscriptions: product.kind == .subscription && !product.isSpecialOffer
        case .tokens: product.kind == .tokens && !product.isSpecialOffer
        case .specialOffer: product.kind == .subscription && product.isSpecialOffer
        }
    }

    private func matches(_ identifier: ProductID, product: RUCatalogProduct) -> Bool {
        product.catalogProductID.rawValue == identifier.rawValue
            || product.appStoreProductID == identifier
    }
}
