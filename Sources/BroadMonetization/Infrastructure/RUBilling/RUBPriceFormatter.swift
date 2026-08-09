import Foundation

public struct RUBPriceFormatter: Sendable {
    public init() {}

    /// Formatting locale affects presentation only. It is never used for RU
    /// eligibility, which remains exclusively App Store storefront based.
    public func string(from money: Money) -> String? {
        guard money.currencyCode == "RUB" else {
            return nil
        }

        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.numberStyle = .currency
        formatter.currencyCode = money.currencyCode
        return formatter.string(from: NSDecimalNumber(decimal: money.amount))
    }
}
