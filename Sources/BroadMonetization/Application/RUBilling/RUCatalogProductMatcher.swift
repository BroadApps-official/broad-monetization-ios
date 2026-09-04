import Foundation

/// A host may explicitly map one app-owned product ID to one backend catalog
/// product ID. The platform default never guesses by period or price.
public protocol RUCatalogProductMappingPolicyProtocol: Sendable {
    func mappedCatalogProductID(
        for product: MonetizationProduct,
        kind: RUCatalogProductKind,
        in catalog: RUCatalogPayload
    ) -> RUCatalogProductID?
}

public struct ExactOnlyRUCatalogProductMappingPolicy: RUCatalogProductMappingPolicyProtocol {
    public init() {}

    public func mappedCatalogProductID(
        for _: MonetizationProduct,
        kind _: RUCatalogProductKind,
        in _: RUCatalogPayload
    ) -> RUCatalogProductID? {
        nil
    }
}

public struct AppOwnedRUCatalogProductMappingPolicy: RUCatalogProductMappingPolicyProtocol {
    private let mappings: [ProductID: RUCatalogProductID]

    public init(mappings: [ProductID: RUCatalogProductID]) {
        self.mappings = mappings
    }

    public func mappedCatalogProductID(
        for product: MonetizationProduct,
        kind _: RUCatalogProductKind,
        in _: RUCatalogPayload
    ) -> RUCatalogProductID? {
        mappings[product.productID]
    }
}

public struct RUCatalogProductMatcher: Sendable {
    private let mappingPolicy: any RUCatalogProductMappingPolicyProtocol

    public init(
        mappingPolicy: any RUCatalogProductMappingPolicyProtocol =
            ExactOnlyRUCatalogProductMappingPolicy()
    ) {
        self.mappingPolicy = mappingPolicy
    }

    /// Exact case-sensitive ID mapping always wins. The default policy returns
    /// no fallback, so the platform never guesses a backend ID from a period.
    /// A host-owned policy may return an explicit catalog ID; it is accepted only
    /// when that exact ID exists in the requested catalog section.
    public func match(
        product: MonetizationProduct,
        kind: RUCatalogProductKind,
        in catalog: RUCatalogPayload
    ) -> RUCatalogProduct? {
        // Marked Special Offer rows never participate in an ordinary paywall.
        // The dedicated matcher below is the only path that may select them.
        let candidates = catalog.products.filter {
            $0.kind == kind && !$0.isSpecialOffer
        }
        let requestedID = product.productID.rawValue

        if let exact = candidates.first(where: {
            $0.catalogProductID.rawValue == requestedID
                || $0.appStoreProductID?.rawValue == requestedID
        }) {
            return exact
        }

        guard let mappedID = mappingPolicy.mappedCatalogProductID(
            for: product,
            kind: kind,
            in: catalog
        ) else {
            return nil
        }

        return candidates.first(where: {
            $0.catalogProductID == mappedID
        })
    }

    /// Generic paywalls can complete only entitlement-backed purchases.
    /// Consumables, token packs, coupons and unknown products require a
    /// separate typed fulfillment authority owned by the host application.
    public func matchPremiumEntitlementProduct(
        _ product: MonetizationProduct,
        in catalog: RUCatalogPayload
    ) -> RUCatalogProduct? {
        switch product.kind {
        case .autoRenewableSubscription, .nonRenewingSubscription, .nonConsumable:
            match(product: product, kind: .subscription, in: catalog)
        case .consumable, .unknown:
            nil
        }
    }

    /// Resolves a Special Offer only when the exact selected Adapty product is
    /// backed by a catalog row explicitly marked by the backend. A normal row is
    /// never substituted when the marker is missing.
    public func matchSpecialOfferProduct(
        _ product: MonetizationProduct,
        in catalog: RUCatalogPayload
    ) -> RUCatalogProduct? {
        let requestedID = product.productID.rawValue
        return catalog.products.first(where: {
            $0.isSpecialOffer
                && ($0.catalogProductID.rawValue == requestedID
                    || $0.appStoreProductID?.rawValue == requestedID)
        })
    }

    /// Returns the marked row only when the backend selected exactly one. An
    /// absent or ambiguous marker fails closed.
    public func uniqueSpecialOfferProduct(
        in catalog: RUCatalogPayload
    ) -> RUCatalogProduct? {
        let markedProducts = catalog.products.filter(\.isSpecialOffer)
        guard markedProducts.count == 1 else {
            return nil
        }
        return markedProducts[0]
    }
}
