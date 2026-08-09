import Foundation

public struct SubscriptionPeriod: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case unit
        case count
    }

    public enum Unit: Codable, Equatable, Sendable {
        case day
        case week
        case month
        case year
        case custom(String)
        case unknown
    }

    public let unit: Unit
    public let count: Int?

    public init(
        unit: Unit,
        count: Int?
    ) {
        if let count {
            precondition(count > 0, "Subscription period count must be positive")
        }

        switch unit {
        case .day, .week, .month, .year:
            precondition(count != nil, "A known subscription period unit requires a count")
        case let .custom(rawUnit):
            let trimmedUnit = rawUnit.trimmingCharacters(in: .whitespacesAndNewlines)
            precondition(!trimmedUnit.isEmpty, "Custom subscription period unit must not be empty")
            precondition(trimmedUnit == rawUnit, "Custom subscription period unit must not contain surrounding whitespace")
        case .unknown:
            break
        }

        self.unit = unit
        self.count = count
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let unit = try container.decode(Unit.self, forKey: .unit)
        let count = try container.decodeIfPresent(Int.self, forKey: .count)
        guard Self.isValid(unit: unit, count: count) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid persisted subscription period"
                )
            )
        }
        self.init(unit: unit, count: count)
    }

    public static func day(_ count: Int = 1) -> SubscriptionPeriod {
        SubscriptionPeriod(unit: .day, count: count)
    }

    public static func week(_ count: Int = 1) -> SubscriptionPeriod {
        SubscriptionPeriod(unit: .week, count: count)
    }

    public static func month(_ count: Int = 1) -> SubscriptionPeriod {
        SubscriptionPeriod(unit: .month, count: count)
    }

    public static func year(_ count: Int = 1) -> SubscriptionPeriod {
        SubscriptionPeriod(unit: .year, count: count)
    }

    public static func custom(
        unit: String,
        count: Int? = nil
    ) -> SubscriptionPeriod {
        SubscriptionPeriod(unit: .custom(unit), count: count)
    }

    public static let unknown = SubscriptionPeriod(unit: .unknown, count: nil)

    private static func isValid(
        unit: Unit,
        count: Int?
    ) -> Bool {
        guard count.map({ $0 > 0 }) != false else {
            return false
        }
        switch unit {
        case .day, .week, .month, .year:
            return count != nil
        case let .custom(rawUnit):
            let trimmedUnit = rawUnit.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmedUnit.isEmpty && trimmedUnit == rawUnit
        case .unknown:
            return true
        }
    }
}
