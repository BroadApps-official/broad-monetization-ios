import BroadCore
import Foundation

public enum PaywallFallbackReason: String, Codable, Equatable, Sendable {
    case notConfigured = "not-configured"
    case cacheMiss = "cache-miss"
    case unavailable
    case timedOut = "timed-out"
    case invalidPayload = "invalid-payload"
    case emptyProducts = "empty-products"
}

/// Captures both the logical placement requested by the feature and the placement
/// that actually supplied the payload. Analytics must keep both values.
public struct PaywallOrigin: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case requestedPlacementID
        case resolvedPlacementID
        case catalogSource
        case fallbackReason
    }

    public let requestedPlacementID: PlacementID
    public let resolvedPlacementID: PlacementID
    public let catalogSource: CatalogSource
    public let fallbackReason: PaywallFallbackReason?

    public init(
        requestedPlacementID: PlacementID,
        resolvedPlacementID: PlacementID,
        catalogSource: CatalogSource,
        fallbackReason: PaywallFallbackReason? = nil
    ) {
        let usedFallback = requestedPlacementID != resolvedPlacementID
        precondition(
            usedFallback == (fallbackReason != nil),
            "A changed paywall placement requires one typed fallback reason"
        )

        self.requestedPlacementID = requestedPlacementID
        self.resolvedPlacementID = resolvedPlacementID
        self.catalogSource = catalogSource
        self.fallbackReason = fallbackReason
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let requestedPlacementID = try container.decode(
            PlacementID.self,
            forKey: .requestedPlacementID
        )
        let resolvedPlacementID = try container.decode(
            PlacementID.self,
            forKey: .resolvedPlacementID
        )
        let fallbackReason = try container.decodeIfPresent(
            PaywallFallbackReason.self,
            forKey: .fallbackReason
        )
        guard (requestedPlacementID != resolvedPlacementID) == (fallbackReason != nil) else {
            throw DecodingError.dataCorruptedError(
                forKey: .fallbackReason,
                in: container,
                debugDescription: "Persisted paywall fallback origin is inconsistent"
            )
        }
        try self.init(
            requestedPlacementID: requestedPlacementID,
            resolvedPlacementID: resolvedPlacementID,
            catalogSource: container.decode(CatalogSource.self, forKey: .catalogSource),
            fallbackReason: fallbackReason
        )
    }

    public var usedFallback: Bool {
        requestedPlacementID != resolvedPlacementID
    }
}

public struct PaywallPayload: Codable, Equatable, Sendable {
    public let presentationID: PaywallPresentationID
    public let paywallReference: PaywallReference
    public let variationID: PaywallVariationID?
    public let origin: PaywallOrigin

    /// Provider order is part of the contract. Duplicate product SKUs and references
    /// are valid and must not be filtered, sorted or deduplicated by any layer.
    public let products: [MonetizationProduct]

    public let remoteConfiguration: RemotePaywallConfiguration
    public let remoteConfigurationProvenance: PaywallRemoteConfigurationProvenance
    public let fetchedAt: Date

    public init(
        presentationID: PaywallPresentationID,
        paywallReference: PaywallReference,
        variationID: PaywallVariationID? = nil,
        origin: PaywallOrigin,
        products: [MonetizationProduct],
        remoteConfiguration: RemotePaywallConfiguration = .empty,
        remoteConfigurationProvenance: PaywallRemoteConfigurationProvenance = .legacyUnqualified,
        fetchedAt: Date
    ) {
        precondition(
            Set(products.map(\.presentationID)).count == products.count,
            "Every product occurrence in a paywall requires a unique presentation ID"
        )
        precondition(
            fetchedAt.timeIntervalSinceReferenceDate.isFinite,
            "Paywall fetch date must be finite"
        )

        self.presentationID = presentationID
        self.paywallReference = paywallReference
        self.variationID = variationID
        self.origin = origin
        self.products = products
        self.remoteConfiguration = remoteConfiguration.qualified(
            by: remoteConfigurationProvenance
        )
        self.remoteConfigurationProvenance = remoteConfigurationProvenance
        self.fetchedAt = fetchedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let presentationID = try container.decode(
            PaywallPresentationID.self,
            forKey: .presentationID
        )
        let origin = try container.decode(PaywallOrigin.self, forKey: .origin)
        let products = try container.decode([MonetizationProduct].self, forKey: .products)
        let fetchedAt = try container.decode(Date.self, forKey: .fetchedAt)
        try Self.validateDecodedPayload(
            origin: origin,
            products: products,
            fetchedAt: fetchedAt,
            container: container
        )

        self.presentationID = presentationID
        paywallReference = try container.decode(
            PaywallReference.self,
            forKey: .paywallReference
        )
        variationID = try container.decodeIfPresent(
            PaywallVariationID.self,
            forKey: .variationID
        )
        self.origin = origin
        self.products = products
        let decodedRemoteConfiguration = try container.decode(
            RemotePaywallConfiguration.self,
            forKey: .remoteConfiguration
        )
        let decodedProvenance = try container.decodeIfPresent(
            PaywallRemoteConfigurationProvenance.self,
            forKey: .remoteConfigurationProvenance
        ) ?? .legacyUnqualified
        remoteConfiguration = decodedRemoteConfiguration.qualified(
            by: decodedProvenance
        )
        remoteConfigurationProvenance = decodedProvenance
        self.fetchedAt = fetchedAt
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(presentationID, forKey: .presentationID)
        try container.encode(paywallReference, forKey: .paywallReference)
        try container.encodeIfPresent(variationID, forKey: .variationID)
        try container.encode(origin, forKey: .origin)
        try container.encode(products, forKey: .products)
        try container.encode(remoteConfiguration, forKey: .remoteConfiguration)
        try container.encode(
            remoteConfigurationProvenance,
            forKey: .remoteConfigurationProvenance
        )
        try container.encode(fetchedAt, forKey: .fetchedAt)
    }

    /// Produces fresh analytics/UI identities while preserving provider order,
    /// duplicate SKUs, product references and the original fetch timestamp.
    /// Cache consumers must call this before presenting a cached payload again;
    /// `LoadPaywallUseCase` enforces the rule at the platform boundary.
    public func preparedForNewPresentation() -> PaywallPayload {
        let newPresentationID = PaywallPresentationID.generated()
        let newProducts = products.map { product in
            product.replacingPresentationID(with: .generated())
        }

        return PaywallPayload(
            presentationID: newPresentationID,
            paywallReference: paywallReference,
            variationID: variationID,
            origin: origin,
            products: newProducts,
            remoteConfiguration: remoteConfiguration,
            remoteConfigurationProvenance: remoteConfigurationProvenance,
            fetchedAt: fetchedAt
        )
    }
}

private extension PaywallPayload {
    enum CodingKeys: String, CodingKey {
        case presentationID
        case paywallReference
        case variationID
        case origin
        case products
        case remoteConfiguration
        case remoteConfigurationProvenance
        case fetchedAt
    }

    static func validateDecodedPayload(
        origin: PaywallOrigin,
        products: [MonetizationProduct],
        fetchedAt: Date,
        container: KeyedDecodingContainer<CodingKeys>
    ) throws {
        guard fetchedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw DecodingError.dataCorruptedError(
                forKey: .fetchedAt,
                in: container,
                debugDescription: "Paywall fetch date must be finite"
            )
        }
        guard Set(products.map(\.presentationID)).count == products.count else {
            throw DecodingError.dataCorruptedError(
                forKey: .products,
                in: container,
                debugDescription: "Paywall product presentation IDs must be unique"
            )
        }
        guard origin.usedFallback == (origin.fallbackReason != nil) else {
            throw DecodingError.dataCorruptedError(
                forKey: .origin,
                in: container,
                debugDescription: "Paywall fallback origin is inconsistent"
            )
        }
    }
}

public struct PaywallLoadRequest: Codable, Equatable, Sendable {
    public let placementID: PlacementID
    public let fallbackPlacementID: PlacementID

    public init(placementID: PlacementID) {
        self.placementID = placementID
        fallbackPlacementID = .main
    }

    public var shouldAttemptFallback: Bool {
        placementID != fallbackPlacementID
    }
}

public enum PaywallLoadOutcome: Equatable, Sendable {
    case loaded(PaywallPayload)
    case unavailable(AppError)
}

public enum PaywallCacheReadOutcome: Equatable, Sendable {
    case fresh(PaywallPayload)
    case stale(PaywallPayload)
    case missing
    case unavailable(AppError)
}

public enum PaywallCacheWriteOutcome: Equatable, Sendable {
    case stored
    case unavailable(AppError)
}
