import Foundation

/// The two device signals used to decide whether RU payment methods may be
/// offered. The first preferred language is the active system language.
public struct RUBillingDeviceContext: Equatable, Sendable {
    public let regionCode: String?
    public let primaryLanguageIdentifier: String?

    public init(
        regionCode: String?,
        primaryLanguageIdentifier: String?
    ) {
        self.regionCode = Self.normalized(regionCode, uppercase: true)
        self.primaryLanguageIdentifier = Self.normalized(
            primaryLanguageIdentifier,
            uppercase: false
        )
    }

    /// One matching signal is enough: Russian device region OR Russian system
    /// language. Adapty's `ru_pay` remains a separate mandatory gate.
    public var isRussian: Bool {
        regionCode == "RU"
            || regionCode == "RUS"
            || primaryLanguageIdentifier == "ru"
            || primaryLanguageIdentifier?.hasPrefix("ru-") == true
            || primaryLanguageIdentifier?.hasPrefix("ru_") == true
    }
}

private extension RUBillingDeviceContext {
    static func normalized(
        _ value: String?,
        uppercase: Bool
    ) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return uppercase ? trimmed.uppercased() : trimmed.lowercased()
    }
}
