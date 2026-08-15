import Foundation

public enum MonetizationIdentifierPolicy {
    /// Prevents provider/backend identifiers from becoming unbounded values in
    /// domain state, persistence or analytics. Count is measured as UTF-8 bytes.
    public static let maximumUTF8Length = 1024

    public static func isValid(_ value: String) -> Bool {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedValue.isEmpty
            && trimmedValue == value
            && value.utf8.count <= maximumUTF8Length
    }
}

public struct PlacementID: RawRepresentable, Codable, Hashable, Sendable, ValidatedMonetizationIdentifier {
    public static let onboarding = PlacementID(rawValue: "onboarding")
    public static let main = PlacementID(rawValue: "main")
    public static let proIcon = PlacementID(rawValue: "pro_icon")
    public static let settings = PlacementID(rawValue: "settings")
    public static let ctr = PlacementID(rawValue: "CTR")
    public static let feature = PlacementID(rawValue: "feature")
    public static let tokens = PlacementID(rawValue: "tokens")
    public static let discount = PlacementID(rawValue: "discount")
    public static let specialOffer = PlacementID(rawValue: "special-offer")

    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = validatedMonetizationIdentifier(rawValue, name: "Placement ID")
    }

    public static func custom(_ rawValue: String) -> PlacementID {
        PlacementID(rawValue: rawValue)
    }
}

public struct ProductID: RawRepresentable, Codable, Hashable, Sendable, ValidatedMonetizationIdentifier {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = validatedMonetizationIdentifier(rawValue, name: "Product ID")
    }
}

/// An opaque reference to the exact provider product that can be purchased.
/// It must not be reconstructed from `ProductID`: two occurrences may share one SKU.
public struct ProductReference: RawRepresentable, Codable, Hashable, Sendable, ValidatedMonetizationIdentifier {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = validatedMonetizationIdentifier(rawValue, name: "Product reference")
    }
}

/// Identity of one product occurrence in one rendered paywall.
/// Unlike `ProductID`, it remains unique when the provider returns duplicate SKUs.
public struct ProductPresentationID: RawRepresentable, Codable, Hashable, Sendable, ValidatedMonetizationIdentifier {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = validatedMonetizationIdentifier(rawValue, name: "Product presentation ID")
    }

    public static func generated() -> ProductPresentationID {
        ProductPresentationID(rawValue: UUID().uuidString.lowercased())
    }
}

/// Identity of one paywall presentation. A newly shown paywall gets a new value,
/// even when its provider payload came from cache.
public struct PaywallPresentationID: RawRepresentable, Codable, Hashable, Sendable, ValidatedMonetizationIdentifier {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = validatedMonetizationIdentifier(rawValue, name: "Paywall presentation ID")
    }

    public static func generated() -> PaywallPresentationID {
        PaywallPresentationID(rawValue: UUID().uuidString.lowercased())
    }
}

/// Stable, provider-opaque reference to a loaded paywall.
public struct PaywallReference: RawRepresentable, Codable, Hashable, Sendable, ValidatedMonetizationIdentifier {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = validatedMonetizationIdentifier(rawValue, name: "Paywall reference")
    }
}

/// Provider-opaque attribution identifier for the variation selected by the
/// monetization provider. Hosts preserve it, but never create, interpret or
/// compare it as an experiment-segment authority.
public struct PaywallVariationID: RawRepresentable, Codable, Hashable, Sendable, ValidatedMonetizationIdentifier {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = validatedMonetizationIdentifier(rawValue, name: "Paywall variation ID")
    }
}

public struct PaywallUIVariantID: RawRepresentable, Codable, Hashable, Sendable, ValidatedMonetizationIdentifier {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = validatedMonetizationIdentifier(rawValue, name: "Paywall UI variant ID")
    }
}

public struct CheckoutSessionID: RawRepresentable, Codable, Hashable, Sendable, ValidatedMonetizationIdentifier {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = validatedMonetizationIdentifier(rawValue, name: "Checkout session ID")
    }
}

/// Random, app-local correlation value for one monetization operation. It is safe
/// for analytics and deliberately does not contain a provider transaction/user ID.
public struct MonetizationAttemptID: RawRepresentable, Codable, Hashable, Sendable, ValidatedMonetizationIdentifier {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = validatedMonetizationIdentifier(rawValue, name: "Monetization attempt ID")
    }

    public static func generated() -> MonetizationAttemptID {
        MonetizationAttemptID(rawValue: UUID().uuidString.lowercased())
    }
}

public struct RUCatalogProductID: RawRepresentable, Codable, Hashable, Sendable, ValidatedMonetizationIdentifier {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = validatedMonetizationIdentifier(rawValue, name: "RU catalog product ID")
    }
}

public struct RUSubscriptionID: RawRepresentable, Codable, Hashable, Sendable, ValidatedMonetizationIdentifier {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = validatedMonetizationIdentifier(rawValue, name: "RU subscription ID")
    }
}

private func validatedMonetizationIdentifier(
    _ rawValue: String,
    name: String
) -> String {
    precondition(
        MonetizationIdentifierPolicy.isValid(rawValue),
        "\(name) must be non-empty, trimmed and bounded"
    )
    return rawValue
}

protocol ValidatedMonetizationIdentifier: RawRepresentable where RawValue == String {}

extension ValidatedMonetizationIdentifier {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        guard MonetizationIdentifierPolicy.isValid(rawValue),
              let value = Self(rawValue: rawValue)
        else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid monetization identifier"
            )
        }
        self = value
    }
}
