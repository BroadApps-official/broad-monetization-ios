import Foundation

@main
enum ProductPricePresentationProbe {
    static func main() {
        let presentations = ProductPricePresenter().presentations(
            for: [
                product(id: "usd-week", amount: "10", currencyCode: "USD"),
                product(id: "rub-week", amount: "100", currencyCode: "RUB"),
                product(id: "usd-month", amount: "21.74", currencyCode: "USD", period: .month())
            ]
        )

        guard presentations.count == 3,
              presentations[0].savingsPercent == nil,
              !presentations[0].isBestValue,
              presentations[1].savingsPercent == nil,
              !presentations[1].isBestValue,
              presentations[2].savingsPercent == 50,
              presentations[2].isBestValue
        else {
            fatalError(
                "Savings must be derived within one currency without comparing USD and RUB amounts"
            )
        }

        print("PASS: product savings are compared only within the same currency")

        probeSingleProductAccessor()
        probePeriodWeeks()
        probePriceLocale()
    }

    private static func probeSingleProductAccessor() {
        let presenter = ProductPricePresenter()
        let weekly = product(id: "week", amount: "6.99", currencyCode: "USD")
        let yearly = product(
            id: "year",
            amount: "49.99",
            currencyCode: "USD",
            period: .year()
        )
        let products = [weekly, yearly]

        let batch = presenter.presentations(for: products)
        guard let single = presenter.presentation(for: yearly, among: products),
              single == batch[1]
        else {
            fatalError("A single product's presentation must match its place in the batch")
        }

        let stranger = product(id: "stranger", amount: "1.99", currencyCode: "USD")
        guard presenter.presentation(for: stranger, among: products) == nil else {
            fatalError("A product outside the compared set has no presentation")
        }

        print("PASS: one product's presentation matches the batch and an outsider has none")
    }

    private static func probePeriodWeeks() {
        let presenter = ProductPricePresenter()
        guard presenter.weeks(in: .week()) == 1,
              presenter.weeks(in: .month()) == ProductPricePresenter.PeriodWeights.standard.weeksPerMonth,
              presenter.weeks(in: .year()) == ProductPricePresenter.PeriodWeights.standard.weeksPerYear,
              presenter.weeks(in: .unknown) == nil
        else {
            fatalError("Period length in weeks must match the presenter's own weights")
        }

        print("PASS: period length in weeks is public and matches the derived weekly price")
    }

    private static func probePriceLocale() {
        let carried = MonetizationProduct(
            presentationID: ProductPresentationID(rawValue: "presentation-locale"),
            reference: ProductReference(rawValue: "reference-locale"),
            productID: ProductID(rawValue: "product-locale"),
            kind: .autoRenewableSubscription,
            price: Money(amount: Decimal(string: "6.99")!, currencyCode: "USD"),
            displayPrice: "US$6.99",
            priceLocaleIdentifier: "en_US",
            subscriptionPeriod: .week(),
            catalogSource: .adapty
        )
        guard carried.priceLocale?.identifier == "en_US" else {
            fatalError("A reported price locale must reach the host")
        }

        let blank = MonetizationProduct(
            presentationID: ProductPresentationID(rawValue: "presentation-blank"),
            reference: ProductReference(rawValue: "reference-blank"),
            productID: ProductID(rawValue: "product-blank"),
            kind: .autoRenewableSubscription,
            priceLocaleIdentifier: "   ",
            catalogSource: .adapty
        )
        guard blank.priceLocaleIdentifier == nil, blank.priceLocale == nil else {
            fatalError("A blank locale identifier must read as absent, not as a locale")
        }

        let encoded = try! JSONEncoder().encode(carried)
        let decoded = try! JSONDecoder().decode(MonetizationProduct.self, from: encoded)
        guard decoded.priceLocaleIdentifier == "en_US" else {
            fatalError("A cached product must keep its price locale")
        }

        var legacyObject = try! JSONSerialization.jsonObject(
            with: encoded
        ) as! [String: Any]
        legacyObject.removeValue(forKey: "priceLocaleIdentifier")
        let legacyPayload = try! JSONSerialization.data(withJSONObject: legacyObject)
        guard let legacy = try? JSONDecoder().decode(
            MonetizationProduct.self,
            from: legacyPayload
        ), legacy.priceLocaleIdentifier == nil
        else {
            fatalError("A cache written before the locale existed must still decode")
        }

        print("PASS: the store's price locale is carried, normalized and cache-compatible")
    }

    private static func product(
        id: String,
        amount: String,
        currencyCode: String,
        period: SubscriptionPeriod = .week()
    ) -> MonetizationProduct {
        MonetizationProduct(
            presentationID: ProductPresentationID(rawValue: "presentation-\(id)"),
            reference: ProductReference(rawValue: "reference-\(id)"),
            productID: ProductID(rawValue: "product-\(id)"),
            kind: .autoRenewableSubscription,
            price: Money(
                amount: Decimal(string: amount)!,
                currencyCode: currencyCode
            ),
            subscriptionPeriod: period,
            catalogSource: .storeKit
        )
    }
}
