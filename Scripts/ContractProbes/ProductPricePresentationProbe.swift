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
