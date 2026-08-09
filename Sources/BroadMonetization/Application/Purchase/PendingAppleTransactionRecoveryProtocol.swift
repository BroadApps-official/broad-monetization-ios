import Foundation

public enum VerifiedApplePurchaseReason: String, Equatable, Sendable {
    case purchase
    case renewal
}

/// A sanitized StoreKit fact. It contains no transaction ID, receipt or user
/// identifier. Construction is reserved for a host adapter after StoreKit JWS
/// verification and its configured app-account ownership check succeeded.
public struct VerifiedApplePurchaseTransaction: Equatable, Sendable {
    public let productID: ProductID
    public let purchaseDate: Date
    public let reason: VerifiedApplePurchaseReason

    public init(
        productID: ProductID,
        purchaseDate: Date,
        reason: VerifiedApplePurchaseReason
    ) {
        precondition(
            purchaseDate.timeIntervalSinceReferenceDate.isFinite,
            "Verified Apple transaction date must be finite"
        )
        self.productID = productID
        self.purchaseDate = purchaseDate
        self.reason = reason
    }
}

public enum PendingAppleTransactionRecoveryOutcome: Equatable, Sendable {
    case matched(VerifiedApplePurchaseTransaction)
    case noMatch
    case unavailable
}

/// Scans verified StoreKit history for an approval that may have completed
/// before a `Transaction.updates` listener started (for example after a cold
/// launch or after an SDK finished the transaction).
public protocol PendingAppleTransactionRecoveryProtocol: Sendable {
    func recover(
        _ intent: PendingApplePurchaseIntent
    ) async -> PendingAppleTransactionRecoveryOutcome
}
