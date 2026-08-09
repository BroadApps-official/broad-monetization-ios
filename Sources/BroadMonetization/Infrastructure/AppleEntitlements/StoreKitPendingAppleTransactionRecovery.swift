import Foundation
import StoreKit

public struct StoreKitPendingAppleTransactionRecovery:
    PendingAppleTransactionRecoveryProtocol {
    private let appBundleIdentifier: String
    private let ownershipPolicy: StoreKitEntitlementOwnershipPolicy
    private let maximumClockSkew: TimeInterval

    public init(
        appBundleIdentifier: String,
        ownershipPolicy: StoreKitEntitlementOwnershipPolicy,
        maximumClockSkew: TimeInterval = 0
    ) {
        precondition(
            MonetizationIdentifierPolicy.isValid(appBundleIdentifier),
            "App bundle identifier must be valid"
        )
        precondition(
            maximumClockSkew.isFinite && maximumClockSkew >= 0,
            "Apple transaction clock-skew tolerance must be finite and non-negative"
        )
        self.appBundleIdentifier = appBundleIdentifier
        self.ownershipPolicy = ownershipPolicy
        self.maximumClockSkew = maximumClockSkew
    }

    public func recover(
        _ intent: PendingApplePurchaseIntent
    ) async -> PendingAppleTransactionRecoveryOutcome {
        var foundRelevantUnverifiedTransaction = false

        for await result in Transaction.unfinished {
            switch evaluate(result, for: intent) {
            case let .matched(transaction):
                return .matched(transaction)
            case .relevantUnverified:
                foundRelevantUnverifiedTransaction = true
            case .irrelevant:
                break
            }
        }

        for await result in Transaction.all {
            guard !Task.isCancelled else {
                return .unavailable
            }
            switch evaluate(result, for: intent) {
            case let .matched(transaction):
                return .matched(transaction)
            case .relevantUnverified:
                foundRelevantUnverifiedTransaction = true
            case .irrelevant:
                break
            }
        }

        return foundRelevantUnverifiedTransaction ? .unavailable : .noMatch
    }
}

private extension StoreKitPendingAppleTransactionRecovery {
    enum Evaluation {
        case matched(VerifiedApplePurchaseTransaction)
        case relevantUnverified
        case irrelevant
    }

    func evaluate(
        _ result: VerificationResult<Transaction>,
        for intent: PendingApplePurchaseIntent
    ) -> Evaluation {
        switch result {
        case let .unverified(transaction, _):
            guard transaction.productID == intent.productID.rawValue,
                  transaction.appBundleID == appBundleIdentifier,
                  transaction.reason == .purchase,
                  transaction.revocationDate == nil,
                  !transaction.isUpgraded,
                  ownershipMatches(transaction),
                  purchaseDateMatches(transaction.purchaseDate, intent: intent)
            else {
                return .irrelevant
            }
            return .relevantUnverified
        case let .verified(transaction):
            guard transaction.productID == intent.productID.rawValue else {
                return .irrelevant
            }
            guard transaction.appBundleID == appBundleIdentifier,
                  transaction.reason == .purchase,
                  transaction.revocationDate == nil,
                  !transaction.isUpgraded,
                  ownershipMatches(transaction),
                  purchaseDateMatches(transaction.purchaseDate, intent: intent)
            else {
                return .irrelevant
            }
            return .matched(
                VerifiedApplePurchaseTransaction(
                    productID: intent.productID,
                    purchaseDate: transaction.purchaseDate,
                    reason: .purchase
                )
            )
        }
    }

    func ownershipMatches(_ transaction: Transaction) -> Bool {
        switch ownershipPolicy {
        case .appStoreAccount:
            true
        case let .appAccountToken(expectedToken):
            transaction.appAccountToken == expectedToken
        }
    }

    func purchaseDateMatches(
        _ purchaseDate: Date,
        intent: PendingApplePurchaseIntent
    ) -> Bool {
        guard purchaseDate.timeIntervalSinceReferenceDate.isFinite else {
            return false
        }
        return purchaseDate.timeIntervalSince(intent.startedAt) >= -maximumClockSkew
    }
}
