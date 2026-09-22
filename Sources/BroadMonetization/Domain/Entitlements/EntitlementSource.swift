public struct EntitlementSource: RawRepresentable, Codable, Hashable, Sendable, ValidatedMonetizationIdentifier {
    public let rawValue: String
    public init(rawValue: String) {
        precondition(MonetizationIdentifierPolicy.isValid(rawValue))
        self.rawValue = rawValue
    }

    public static let apple = Self(rawValue: "apple")
    public static let primaryBackend = Self(rawValue: "primary-backend")
}
