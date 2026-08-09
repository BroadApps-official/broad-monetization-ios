import Foundation

public struct AdaptyMonetizationMessages: Sendable {
    public let activationUnavailable: String
    public let paywallUnavailable: String
    public let productUnavailable: String
    public let purchaseFailed: String
    public let restoreFailed: String

    public init(
        activationUnavailable: String,
        paywallUnavailable: String,
        productUnavailable: String,
        purchaseFailed: String,
        restoreFailed: String
    ) {
        let messages = [
            activationUnavailable,
            paywallUnavailable,
            productUnavailable,
            purchaseFailed,
            restoreFailed
        ]
        precondition(
            messages.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
            "Adapty user-facing messages must not be empty"
        )

        self.activationUnavailable = activationUnavailable
        self.paywallUnavailable = paywallUnavailable
        self.productUnavailable = productUnavailable
        self.purchaseFailed = purchaseFailed
        self.restoreFailed = restoreFailed
    }
}
