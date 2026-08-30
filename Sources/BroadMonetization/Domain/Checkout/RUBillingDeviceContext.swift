import Foundation

/// Device metadata used by the RU billing gate.
///
/// Only the selected iPhone region participates in eligibility. The language
/// remains available for source compatibility and presentation, but it must
/// never enable a financial route.
public struct RUBillingDeviceContext: Equatable, Sendable {
    public let regionCode: String?
    public let primaryLanguageIdentifier: String?

    public init(regionCode: String?) {
        self.init(
            regionCode: regionCode,
            primaryLanguageIdentifier: nil
        )
    }

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

    /// `true` only when the region selected on the iPhone is Russian.
    ///
    /// App Store storefront eligibility is evaluated separately by
    /// `RUBillingGate`. Adapty's explicit `ru_pay = true` remains mandatory.
    public var isRussian: Bool {
        regionCode == "RU"
            || regionCode == "RUS"
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
