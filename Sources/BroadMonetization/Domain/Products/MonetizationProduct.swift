import Foundation

public enum CatalogSource: String, Codable, Equatable, Sendable {
    case adapty
    case storeKit = "store-kit"
    case ruBackend = "ru-backend"
    case cache
}

public enum MonetizationProductKind: String, Codable, Equatable, Sendable {
    case autoRenewableSubscription = "auto-renewable-subscription"
    case nonRenewingSubscription = "non-renewing-subscription"
    case nonConsumable = "non-consumable"
    case consumable
    case unknown
}

public struct MonetizationProduct: Identifiable, Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case presentationID
        case reference
        case productID
        case commercialFingerprint
        case kind
        case title
        case subtitle
        case price
        case displayPrice
        case subscriptionPeriod
        case catalogSource
    }

    public var id: ProductPresentationID {
        presentationID
    }

    /// Unique identity of this exact occurrence in the current product array.
    public let presentationID: ProductPresentationID

    /// Opaque handle used by a repository to resolve the provider product.
    public let reference: ProductReference

    /// Stable StoreKit/provider SKU. It is deliberately not used as UI identity.
    public let productID: ProductID
    /// Opaque, deterministic snapshot of provider product and offer terms.
    /// Cached presentations require an exact match before a raw purchase handle
    /// may be rehydrated, preventing a silent purchase of changed terms.
    public let commercialFingerprint: String?
    public let kind: MonetizationProductKind
    public let title: String?
    public let subtitle: String?
    public let price: Money?
    public let displayPrice: String?
    public let subscriptionPeriod: SubscriptionPeriod
    public let catalogSource: CatalogSource

    /// Whether the shared premium checkout can safely start for this product.
    ///
    /// Every provider occurrence remains visible in the paywall, including
    /// malformed and unsupported products. A verified numeric price is the
    /// financial boundary, however: provider display text alone must never be
    /// enough to open a payment sheet. Consumables require a dedicated durable
    /// fulfillment composition and unknown kinds are also fail-closed.
    public var isEligibleForGenericPurchase: Bool {
        guard price != nil else {
            return false
        }

        switch kind {
        case .autoRenewableSubscription, .nonRenewingSubscription, .nonConsumable:
            return true
        case .consumable, .unknown:
            return false
        }
    }

    public init(
        presentationID: ProductPresentationID,
        reference: ProductReference,
        productID: ProductID,
        commercialFingerprint: String? = nil,
        kind: MonetizationProductKind,
        title: String? = nil,
        subtitle: String? = nil,
        price: Money? = nil,
        displayPrice: String? = nil,
        subscriptionPeriod: SubscriptionPeriod = .unknown,
        catalogSource: CatalogSource
    ) {
        precondition(
            commercialFingerprint.map(MonetizationIdentifierPolicy.isValid) != false,
            "Commercial fingerprint must be non-empty, trimmed and bounded"
        )
        self.presentationID = presentationID
        self.reference = reference
        self.productID = productID
        self.commercialFingerprint = commercialFingerprint
        self.kind = kind
        self.title = title.nonBlank
        self.subtitle = subtitle.nonBlank
        self.price = price
        self.displayPrice = displayPrice.nonBlank
        self.subscriptionPeriod = subscriptionPeriod
        self.catalogSource = catalogSource
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let commercialFingerprint = try container.decodeIfPresent(
            String.self,
            forKey: .commercialFingerprint
        )
        guard commercialFingerprint.map(MonetizationIdentifierPolicy.isValid) != false else {
            throw DecodingError.dataCorruptedError(
                forKey: .commercialFingerprint,
                in: container,
                debugDescription: "Invalid persisted commercial fingerprint"
            )
        }
        try self.init(
            presentationID: container.decode(
                ProductPresentationID.self,
                forKey: .presentationID
            ),
            reference: container.decode(ProductReference.self, forKey: .reference),
            productID: container.decode(ProductID.self, forKey: .productID),
            commercialFingerprint: commercialFingerprint,
            kind: container.decode(MonetizationProductKind.self, forKey: .kind),
            title: container.decodeIfPresent(String.self, forKey: .title),
            subtitle: container.decodeIfPresent(String.self, forKey: .subtitle),
            price: container.decodeIfPresent(Money.self, forKey: .price),
            displayPrice: container.decodeIfPresent(String.self, forKey: .displayPrice),
            subscriptionPeriod: container.decode(
                SubscriptionPeriod.self,
                forKey: .subscriptionPeriod
            ),
            catalogSource: container.decode(CatalogSource.self, forKey: .catalogSource)
        )
    }

    public func replacingPresentationID(
        with presentationID: ProductPresentationID
    ) -> MonetizationProduct {
        MonetizationProduct(
            presentationID: presentationID,
            reference: reference,
            productID: productID,
            commercialFingerprint: commercialFingerprint,
            kind: kind,
            title: title,
            subtitle: subtitle,
            price: price,
            displayPrice: displayPrice,
            subscriptionPeriod: subscriptionPeriod,
            catalogSource: catalogSource
        )
    }
}

private extension String? {
    var nonBlank: String? {
        guard let value = self else {
            return nil
        }

        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
    }
}
