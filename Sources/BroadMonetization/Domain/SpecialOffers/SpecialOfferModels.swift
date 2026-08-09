import Foundation

/// One safety boundary for every host, remote and persisted special-offer
/// duration. The limit is intentionally much larger than a realistic campaign,
/// while remaining safely representable by `Duration`, `Date` and UI counters.
public enum SpecialOfferDurationPolicy: Sendable {
    public static let maximumDuration: TimeInterval = 10 * 365 * 24 * 60 * 60

    public static func isValid(_ duration: TimeInterval) -> Bool {
        duration.isFinite && duration > 0 && duration <= maximumDuration
    }
}

/// Host-owned opt-in configuration. Passing `nil` means the feature does not exist
/// for that app and must not trigger loading, timers, persistence or fallback values.
public struct SpecialOfferConfiguration: Codable, Equatable, Sendable {
    public let placementID: PlacementID
    public let windowDuration: TimeInterval?
    public let cooldownDuration: TimeInterval?

    public init(
        placementID: PlacementID,
        windowDuration: TimeInterval? = nil,
        cooldownDuration: TimeInterval? = nil
    ) {
        Self.validateOptionalDuration(windowDuration, name: "Special-offer window duration")
        Self.validateOptionalDuration(cooldownDuration, name: "Special-offer cooldown duration")

        self.placementID = placementID
        self.windowDuration = windowDuration
        self.cooldownDuration = cooldownDuration
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let placementID = try container.decode(PlacementID.self, forKey: .placementID)
        let windowDuration = try container.decodeIfPresent(
            TimeInterval.self,
            forKey: .windowDuration
        )
        let cooldownDuration = try container.decodeIfPresent(
            TimeInterval.self,
            forKey: .cooldownDuration
        )
        guard Self.isValidOptionalDuration(windowDuration),
              Self.isValidOptionalDuration(cooldownDuration)
        else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid persisted special-offer configuration"
                )
            )
        }
        self.init(
            placementID: placementID,
            windowDuration: windowDuration,
            cooldownDuration: cooldownDuration
        )
    }

    private static func validateOptionalDuration(
        _ duration: TimeInterval?,
        name: String
    ) {
        guard let duration else {
            return
        }

        precondition(
            SpecialOfferDurationPolicy.isValid(duration),
            "\(name) must be finite, positive and within the supported limit"
        )
    }

    private static func isValidOptionalDuration(
        _ duration: TimeInterval?
    ) -> Bool {
        duration.map(SpecialOfferDurationPolicy.isValid) ?? true
    }
}

/// Typed values parsed from a special-offer remote payload.
/// Every display value is optional: the platform never invents crossed prices,
/// multipliers or period text when a project did not configure them.
public struct SpecialOfferRemoteConfiguration: Codable, Equatable, Sendable {
    public let isEnabled: Bool
    public let windowDuration: TimeInterval?
    public let cooldownDuration: TimeInterval?
    public let crossedPrice: String?
    public let crossedValue: Decimal?
    public let priceMultiplier: Decimal?
    public let periodText: String?
    public let badge: String?

    public init(
        isEnabled: Bool,
        windowDuration: TimeInterval? = nil,
        cooldownDuration: TimeInterval? = nil,
        crossedPrice: String? = nil,
        crossedValue: Decimal? = nil,
        priceMultiplier: Decimal? = nil,
        periodText: String? = nil,
        badge: String? = nil
    ) {
        Self.validateOptionalDuration(windowDuration, name: "Remote special-offer window duration")
        Self.validateOptionalDuration(cooldownDuration, name: "Remote special-offer cooldown duration")
        Self.validateOptionalDecimal(crossedValue, name: "Remote special-offer crossed value")
        Self.validateOptionalDecimal(priceMultiplier, name: "Remote special-offer price multiplier")

        self.isEnabled = isEnabled
        self.windowDuration = windowDuration
        self.cooldownDuration = cooldownDuration
        self.crossedPrice = crossedPrice.nonBlank
        self.crossedValue = crossedValue
        self.priceMultiplier = priceMultiplier
        self.periodText = periodText.nonBlank
        self.badge = badge.nonBlank
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let windowDuration = try container.decodeIfPresent(
            TimeInterval.self,
            forKey: .windowDuration
        )
        let cooldownDuration = try container.decodeIfPresent(
            TimeInterval.self,
            forKey: .cooldownDuration
        )
        let crossedValue = try container.decodeIfPresent(
            Decimal.self,
            forKey: .crossedValue
        )
        let priceMultiplier = try container.decodeIfPresent(
            Decimal.self,
            forKey: .priceMultiplier
        )
        guard Self.isValidOptionalDuration(windowDuration),
              Self.isValidOptionalDuration(cooldownDuration),
              Self.isValidOptionalDecimal(crossedValue),
              Self.isValidOptionalDecimal(priceMultiplier)
        else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid persisted remote special-offer configuration"
                )
            )
        }
        try self.init(
            isEnabled: container.decode(Bool.self, forKey: .isEnabled),
            windowDuration: windowDuration,
            cooldownDuration: cooldownDuration,
            crossedPrice: container.decodeIfPresent(String.self, forKey: .crossedPrice),
            crossedValue: crossedValue,
            priceMultiplier: priceMultiplier,
            periodText: container.decodeIfPresent(String.self, forKey: .periodText),
            badge: container.decodeIfPresent(String.self, forKey: .badge)
        )
    }

    private static func validateOptionalDuration(
        _ duration: TimeInterval?,
        name: String
    ) {
        guard let duration else {
            return
        }

        precondition(
            SpecialOfferDurationPolicy.isValid(duration),
            "\(name) must be finite, positive and within the supported limit"
        )
    }

    private static func validateOptionalDecimal(
        _ value: Decimal?,
        name: String
    ) {
        guard let value else {
            return
        }

        precondition(!value.isNaN && value > 0, "\(name) must be positive")
    }

    private static func isValidOptionalDuration(
        _ duration: TimeInterval?
    ) -> Bool {
        duration.map(SpecialOfferDurationPolicy.isValid) ?? true
    }

    private static func isValidOptionalDecimal(
        _ value: Decimal?
    ) -> Bool {
        value.map { !$0.isNaN && $0 > 0 } ?? true
    }
}

public struct SpecialOfferWindow: Codable, Equatable, Sendable {
    public let startedAt: Date
    public let expiresAt: Date

    public init(
        startedAt: Date,
        expiresAt: Date
    ) {
        precondition(
            startedAt.timeIntervalSinceReferenceDate.isFinite
                && expiresAt.timeIntervalSinceReferenceDate.isFinite
                && expiresAt > startedAt
                && SpecialOfferDurationPolicy.isValid(
                    expiresAt.timeIntervalSince(startedAt)
                ),
            "Special-offer window dates must be finite, ordered and within the supported limit"
        )
        self.startedAt = startedAt
        self.expiresAt = expiresAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let startedAt = try container.decode(Date.self, forKey: .startedAt)
        let expiresAt = try container.decode(Date.self, forKey: .expiresAt)
        guard startedAt.timeIntervalSinceReferenceDate.isFinite,
              expiresAt.timeIntervalSinceReferenceDate.isFinite,
              expiresAt > startedAt,
              SpecialOfferDurationPolicy.isValid(
                  expiresAt.timeIntervalSince(startedAt)
              )
        else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid persisted special-offer window"
                )
            )
        }
        self.init(startedAt: startedAt, expiresAt: expiresAt)
    }
}

public enum SpecialOfferUnavailableReason: String, Codable, Equatable, Sendable {
    case notConfigured = "not-configured"
    case disabledByRemoteConfiguration = "disabled-by-remote-configuration"
    case ineligible
    case paywallUnavailable = "paywall-unavailable"
    case persistenceUnavailable = "persistence-unavailable"
    case untrustedTime = "untrusted-time"
}

public enum SpecialOfferState: Codable, Equatable, Sendable {
    case unavailable(SpecialOfferUnavailableReason)
    case eligible
    case active(SpecialOfferWindow)
    case expired(date: Date)
    case cooldown(until: Date)

    public init(from decoder: any Decoder) throws {
        let representation = try CodableRepresentation(from: decoder)
        switch representation {
        case let .unavailable(reason):
            self = .unavailable(reason)
        case .eligible:
            self = .eligible
        case let .active(window):
            self = .active(window)
        case let .expired(date):
            guard date.timeIntervalSinceReferenceDate.isFinite else {
                throw Self.invalidDate(decoder)
            }
            self = .expired(date: date)
        case let .cooldown(date):
            guard date.timeIntervalSinceReferenceDate.isFinite else {
                throw Self.invalidDate(decoder)
            }
            self = .cooldown(until: date)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        let representation: CodableRepresentation = switch self {
        case let .unavailable(reason):
            .unavailable(reason)
        case .eligible:
            .eligible
        case let .active(window):
            .active(window)
        case let .expired(date):
            .expired(date: date)
        case let .cooldown(date):
            .cooldown(until: date)
        }
        try representation.encode(to: encoder)
    }
}

private extension SpecialOfferState {
    enum CodableRepresentation: Codable {
        case unavailable(SpecialOfferUnavailableReason)
        case eligible
        case active(SpecialOfferWindow)
        case expired(date: Date)
        case cooldown(until: Date)
    }

    static func invalidDate(_ decoder: any Decoder) -> DecodingError {
        DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Persisted special-offer date must be finite"
            )
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
