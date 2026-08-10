import BroadCore
import Foundation

/// Verified StoreKit evidence sent to the application's token backend. The
/// backend must deduplicate `transactionID`; the device balance is never the
/// source of truth.
public struct TokenTransactionEvidence: Codable, Equatable, Sendable {
    public let transactionID: String
    public let productID: ProductID
    public let signedTransaction: String
    public let purchasedAt: Date

    public init(
        transactionID: String,
        productID: ProductID,
        signedTransaction: String,
        purchasedAt: Date
    ) {
        precondition(
            MonetizationIdentifierPolicy.isValid(transactionID),
            "Token transaction ID must be valid"
        )
        precondition(
            !signedTransaction.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty,
            "Token transaction evidence must not be empty"
        )
        precondition(
            purchasedAt.timeIntervalSinceReferenceDate.isFinite,
            "Token purchase date must be finite"
        )
        self.transactionID = transactionID
        self.productID = productID
        self.signedTransaction = signedTransaction
        self.purchasedAt = purchasedAt
    }
}

public struct TokenBalanceSnapshot: Codable, Equatable, Sendable {
    public let balance: Decimal
    public let updatedAt: Date

    public init(balance: Decimal, updatedAt: Date) {
        precondition(
            !balance.isNaN && balance >= 0,
            "Token balance must be non-negative"
        )
        precondition(
            updatedAt.timeIntervalSinceReferenceDate.isFinite,
            "Token balance date must be finite"
        )
        self.balance = balance
        self.updatedAt = updatedAt
    }
}

public struct TokenFulfillmentRequest: Codable, Equatable, Sendable {
    public let attemptID: MonetizationAttemptID
    public let evidence: TokenTransactionEvidence

    public init(
        attemptID: MonetizationAttemptID,
        evidence: TokenTransactionEvidence
    ) {
        self.attemptID = attemptID
        self.evidence = evidence
    }
}

public enum TokenFulfillmentOutcome: Equatable, Sendable {
    case credited(TokenBalanceSnapshot)
    case alreadyCredited(TokenBalanceSnapshot)
    case pending
    case unavailable(AppError)
    case failed(AppError)
}

public protocol TokenFulfillmentRepositoryProtocol: Sendable {
    /// Sends verified evidence to the app backend. Implementations must make
    /// the request idempotent by transaction ID and return backend balance.
    func fulfill(
        _ request: TokenFulfillmentRequest
    ) async -> TokenFulfillmentOutcome
}

public enum TokenEvidenceResolution: Equatable, Sendable {
    case verified(TokenTransactionEvidence)
    case notFound
    case unavailable
}

public protocol TokenTransactionEvidenceProviderProtocol: Sendable {
    func evidence(
        productID: ProductID,
        purchasedAfter: Date
    ) async -> TokenEvidenceResolution
}

public struct PendingTokenPurchaseIntent: Codable, Equatable, Sendable {
    public let analyticsContext: PurchaseAnalyticsContext
    public let startedAt: Date
    public let evidence: TokenTransactionEvidence?
    public let belongsToCurrentSubject: Bool

    public var attemptID: MonetizationAttemptID {
        analyticsContext.attemptID
    }

    public var productID: ProductID {
        analyticsContext.productID
    }

    public init(
        analyticsContext: PurchaseAnalyticsContext,
        startedAt: Date,
        evidence: TokenTransactionEvidence?,
        belongsToCurrentSubject: Bool
    ) {
        precondition(
            startedAt.timeIntervalSinceReferenceDate.isFinite,
            "Pending token purchase date must be finite"
        )
        self.analyticsContext = analyticsContext
        self.startedAt = startedAt
        self.evidence = evidence
        self.belongsToCurrentSubject = belongsToCurrentSubject
    }
}

public enum PendingTokenPurchaseState: Equatable, Sendable {
    case none
    case pending(PendingTokenPurchaseIntent)
    case unavailable
}

public protocol PendingTokenPurchaseStoreProtocol:
    PendingOperationBlockerProtocol {
    func begin(context: PurchaseAnalyticsContext) async -> Bool
    func state() async -> PendingTokenPurchaseState
    func save(
        evidence: TokenTransactionEvidence,
        attemptID: MonetizationAttemptID
    ) async -> Bool
    func clear(attemptID: MonetizationAttemptID) async -> Bool
}

public extension PendingTokenPurchaseStoreProtocol {
    func hasPendingMonetizationOperation() async -> Bool {
        switch await state() {
        case .pending, .unavailable:
            true
        case .none:
            false
        }
    }
}

public enum TokenPurchaseOutcome: Equatable, Sendable {
    case credited(TokenBalanceSnapshot)
    case cancelled
    case pending
    case failed(AppError)
}
