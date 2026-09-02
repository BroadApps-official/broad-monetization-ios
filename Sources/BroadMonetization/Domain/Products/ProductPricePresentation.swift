import Foundation

/// Derived, provider-neutral price figures for a paywall row: the price of a
/// subscription brought to one week and how much cheaper that week is than the
/// most expensive plan shown alongside it, plus which single row deserves the
/// best-value badge.
///
/// No provider carries these numbers, so hosts previously computed them by hand
/// next to the purchase button. They are derived here from each product's
/// verified ``MonetizationProduct/price`` and ``MonetizationProduct/subscriptionPeriod``.
///
/// Everything fails closed: a product without a decoded amount or with a period
/// that cannot be normalized (``SubscriptionPeriod/Unit/custom(_:)`` or
/// ``SubscriptionPeriod/Unit/unknown``) simply loses the extras instead of
/// showing a guessed figure. Savings are compared only with products in the same
/// currency; amounts in different currencies are never compared. Rendering the
/// numbers into localized strings stays a presentation concern for the UI layer;
/// this type carries only figures.
public struct ProductPricePresentation: Equatable, Sendable {
    /// The occurrence this presentation was computed for.
    public let presentationID: ProductPresentationID

    /// The price of one billing period expressed per week, in the product's own
    /// currency. `nil` when the product has no decoded ``Money`` or a period that
    /// cannot be normalized to weeks.
    public let weeklyPrice: Money?

    /// Whole-percent saving of this plan's weekly price against the most
    /// expensive weekly price among the compared products. `nil` when there is
    /// nothing more expensive to measure against, so no discount can be claimed.
    public let savingsPercent: Int?

    /// Whether this occurrence carries the single best-value badge: the plan
    /// with the largest saving. At most one product in a compared set is marked.
    public let isBestValue: Bool

    public init(
        presentationID: ProductPresentationID,
        weeklyPrice: Money? = nil,
        savingsPercent: Int? = nil,
        isBestValue: Bool = false
    ) {
        self.presentationID = presentationID
        self.weeklyPrice = weeklyPrice
        self.savingsPercent = savingsPercent
        self.isBestValue = isBestValue
    }
}

/// Computes ``ProductPricePresentation`` values for a paywall's product array.
///
/// Savings and the best-value badge are relative to the whole set, so the
/// presenter always works over the full array and compares weekly prices across
/// plans of different lengths on a common per-week basis. The provider array is
/// never filtered, sorted or deduplicated; results are returned in input order.
public struct ProductPricePresenter: Sendable {
    private struct WeeklyRate {
        let amount: Decimal
        let currencyCode: String
    }

    /// How many weeks a month and a year are treated as when bringing a plan to
    /// a weekly price. Defaults match the average Gregorian month and year so a
    /// yearly plan is not flattered by a naive 4-weeks-a-month assumption.
    public struct PeriodWeights: Equatable, Sendable {
        public let weeksPerMonth: Decimal
        public let weeksPerYear: Decimal

        public init(
            weeksPerMonth: Decimal = Decimal(string: "4.348")!,
            weeksPerYear: Decimal = Decimal(string: "52.179")!
        ) {
            precondition(
                weeksPerMonth > 0 && weeksPerYear > 0,
                "Period weights must be positive"
            )
            self.weeksPerMonth = weeksPerMonth
            self.weeksPerYear = weeksPerYear
        }

        public static let standard = PeriodWeights()
    }

    public let periodWeights: PeriodWeights

    public init(periodWeights: PeriodWeights = .standard) {
        self.periodWeights = periodWeights
    }

    /// Derives a presentation for every product, comparing weekly prices across
    /// the whole set. Results align one-to-one with `products`, in the same order.
    public func presentations(
        for products: [MonetizationProduct]
    ) -> [ProductPricePresentation] {
        let rates = products.map(weeklyRate(for:))
        let references = referenceRatesByCurrency(in: rates)
        let savingsList: [Int?] = rates.map { rate in
            guard let rate else {
                return nil
            }
            return savings(
                of: rate.amount,
                comparedTo: references[rate.currencyCode]
            )
        }
        let bestValueIndex = indexOfBestValue(in: savingsList)

        return products.enumerated().map { index, product in
            let weeklyPrice = rates[index].map { rate in
                Money(amount: rate.amount, currencyCode: rate.currencyCode)
            }
            return ProductPricePresentation(
                presentationID: product.presentationID,
                weeklyPrice: weeklyPrice,
                savingsPercent: savingsList[index],
                isBestValue: index == bestValueIndex
            )
        }
    }

    // MARK: - Derivation

    /// The index carrying the badge: the single largest positive saving. `nil`
    /// when no plan is cheaper than another, so the badge would be meaningless.
    private func indexOfBestValue(in savings: [Int?]) -> Int? {
        var bestIndex: Int?
        var bestSavings = 0
        for (index, value) in savings.enumerated() {
            guard let value, value > bestSavings else {
                continue
            }
            bestSavings = value
            bestIndex = index
        }
        return bestIndex
    }

    private func referenceRatesByCurrency(
        in rates: [WeeklyRate?]
    ) -> [String: Decimal] {
        rates.compactMap { $0 }.reduce(into: [:]) { references, rate in
            references[rate.currencyCode] = max(
                references[rate.currencyCode] ?? rate.amount,
                rate.amount
            )
        }
    }

    private func weeklyRate(for product: MonetizationProduct) -> WeeklyRate? {
        guard
            let money = product.price,
            let weeks = weeks(in: product.subscriptionPeriod),
            weeks > 0
        else {
            return nil
        }

        return WeeklyRate(
            amount: money.amount / weeks,
            currencyCode: money.currencyCode
        )
    }

    private func weeks(in period: SubscriptionPeriod) -> Decimal? {
        guard let count = period.count else {
            return nil
        }

        let multiplier = Decimal(count)
        switch period.unit {
        case .day:
            return multiplier / 7
        case .week:
            return multiplier
        case .month:
            return multiplier * periodWeights.weeksPerMonth
        case .year:
            return multiplier * periodWeights.weeksPerYear
        case .custom, .unknown:
            return nil
        }
    }

    private func savings(of rate: Decimal?, comparedTo reference: Decimal?) -> Int? {
        guard
            let rate,
            let reference,
            reference > 0,
            rate < reference
        else {
            return nil
        }

        let ratio = (reference - rate) / reference * 100
        let percent = Int(NSDecimalNumber(decimal: ratio).doubleValue.rounded())
        return percent > 0 ? percent : nil
    }
}
