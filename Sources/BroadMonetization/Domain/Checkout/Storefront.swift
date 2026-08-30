import BroadCore
import Foundation

public struct Storefront: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case identifier
        case countryCode
    }

    public let identifier: String?
    public let countryCode: String

    public init(
        identifier: String? = nil,
        countryCode: String
    ) {
        let normalizedCountryCode = countryCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        precondition(
            (2 ... 3).contains(normalizedCountryCode.count) && normalizedCountryCode.allSatisfy { $0.isASCII && $0.isLetter },
            "Storefront country code must be an ISO 3166-1 alpha-2 or alpha-3 code"
        )

        self.identifier = identifier.nonBlank
        self.countryCode = normalizedCountryCode
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let countryCode = try container.decode(String.self, forKey: .countryCode)
        let normalizedCode = countryCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard (2 ... 3).contains(normalizedCode.count),
              normalizedCode.allSatisfy({ $0.isASCII && $0.isLetter })
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .countryCode,
                in: container,
                debugDescription: "Invalid persisted storefront country code"
            )
        }
        try self.init(
            identifier: container.decodeIfPresent(String.self, forKey: .identifier),
            countryCode: countryCode
        )
    }

    /// A Russian App Store storefront is one of the two positive regional
    /// signals accepted by the RU billing gate.
    public var isRussian: Bool {
        countryCode == "RU" || countryCode == "RUS"
    }
}

public enum StorefrontResolution: Equatable, Sendable {
    case available(Storefront)
    case unavailable(AppError)
}

private extension String? {
    var nonBlank: String? {
        guard let value = self else {
            return nil
        }

        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
    }
}
