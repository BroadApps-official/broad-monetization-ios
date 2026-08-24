import Foundation

/// Describes what the platform can prove about the payload carrying remote
/// configuration.
///
/// Remote feature gates decide which presentation the app may offer. They do
/// not prove a purchase, token balance or premium entitlement. Financial access
/// is always resolved independently by the authoritative entitlement engine.
public enum PaywallRemoteConfigurationProvenance: String, Codable, Equatable, Sendable {
    /// A host-controlled transport proved that this exact response came from a
    /// remote authority for the current request.
    case verifiedFreshRemote = "verified-fresh-remote"

    /// The provider API may silently substitute its own cache or fallback file.
    case providerCacheFallbackPossible = "provider-cache-fallback-possible"

    /// BroadMonetization deliberately restored the whole paywall from its cache.
    case platformCache = "platform-cache"

    /// Backward-compatible value for payloads persisted before provenance was
    /// introduced, and for custom repositories that have not qualified it yet.
    case legacyUnqualified = "legacy-unqualified"

    /// Whether this provider payload may authorize the second-paywall flow.
    /// Adapty may transparently use its own managed cache, so its current
    /// response remains a valid `special_offer` decision. A payload restored by
    /// BroadMonetization itself never re-enables the offer.
    public var authorizesSpecialOfferPresentation: Bool {
        switch self {
        case .verifiedFreshRemote, .providerCacheFallbackPossible:
            true
        case .platformCache, .legacyUnqualified:
            false
        }
    }

    /// RU Billing stays fail-closed unless the exact payload is proven fresh.
    /// This authority is deliberately stricter than Special Offer authority.
    public var authorizesRUBillingPresentation: Bool {
        self == .verifiedFreshRemote
    }

    @available(
        *,
        deprecated,
        message: "Use authorizesSpecialOfferPresentation or authorizesRUBillingPresentation"
    )
    public var authorizesProviderManagedFeatureGates: Bool {
        authorizesSpecialOfferPresentation
    }

    @available(
        *,
        deprecated,
        message: "Use the dedicated Special Offer or RU Billing capability"
    )
    public var authorizesTimeSensitiveFeatures: Bool {
        self == .verifiedFreshRemote
    }
}
