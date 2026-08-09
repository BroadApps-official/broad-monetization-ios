import Foundation

public struct Money: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case amount
        case currencyCode
    }

    public let amount: Decimal
    public let currencyCode: String

    public init(
        amount: Decimal,
        currencyCode: String
    ) {
        let normalizedCode = currencyCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        precondition(!amount.isNaN && amount >= 0, "Money amount must be a non-negative number")
        precondition(
            normalizedCode.count == 3 && normalizedCode.allSatisfy { $0.isASCII && $0.isLetter },
            "Money currency code must be a three-character ISO 4217 code"
        )

        self.amount = amount
        self.currencyCode = normalizedCode
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let amount = try container.decode(Decimal.self, forKey: .amount)
        let currencyCode = try container.decode(String.self, forKey: .currencyCode)
        let normalizedCode = currencyCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard !amount.isNaN,
              amount >= 0,
              normalizedCode.count == 3,
              normalizedCode.allSatisfy({ $0.isASCII && $0.isLetter })
        else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid persisted money value"
                )
            )
        }
        self.init(amount: amount, currencyCode: currencyCode)
    }
}
