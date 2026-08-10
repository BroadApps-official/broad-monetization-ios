import Foundation
import StoreKit

/// Finds the verified consumable transaction after Adapty/StoreKit reports a
/// completed purchase. It does not finish transactions; the purchase adapter
/// remains their sole owner.
public struct StoreKitTokenTransactionEvidenceProvider:
    TokenTransactionEvidenceProviderProtocol {
    private let appBundleIdentifier: String
    private let ownershipPolicy: StoreKitEntitlementOwnershipPolicy
    private let maximumClockSkew: TimeInterval

    public init(
        appBundleIdentifier: String,
        ownershipPolicy: StoreKitEntitlementOwnershipPolicy,
        maximumClockSkew: TimeInterval = 0
    ) {
        let normalizedBundle = appBundleIdentifier.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        precondition(
            !normalizedBundle.isEmpty && normalizedBundle == appBundleIdentifier,
            "App bundle identifier must be valid"
        )
        precondition(
            maximumClockSkew.isFinite && maximumClockSkew >= 0,
            "Token purchase clock skew must be finite and non-negative"
        )
        self.appBundleIdentifier = appBundleIdentifier
        self.ownershipPolicy = ownershipPolicy
        self.maximumClockSkew = maximumClockSkew
    }

    public func evidence(
        productID: ProductID,
        purchasedAfter: Date
    ) async -> TokenEvidenceResolution {
        var foundRelevantUnverified = false

        for await result in Transaction.all {
            guard !Task.isCancelled else {
                return .unavailable
            }

            switch result {
            case let .unverified(transaction, _):
                if isRelevant(
                    transaction,
                    productID: productID,
                    purchasedAfter: purchasedAfter
                ) {
                    foundRelevantUnverified = true
                }
            case let .verified(transaction):
                guard isRelevant(
                    transaction,
                    productID: productID,
                    purchasedAfter: purchasedAfter
                ) else {
                    continue
                }
                return .verified(
                    TokenTransactionEvidence(
                        transactionID: String(transaction.id),
                        productID: productID,
                        signedTransaction: result.jwsRepresentation,
                        purchasedAt: transaction.purchaseDate
                    )
                )
            }
        }

        return foundRelevantUnverified ? .unavailable : .notFound
    }

    private func isRelevant(
        _ transaction: Transaction,
        productID: ProductID,
        purchasedAfter: Date
    ) -> Bool {
        transaction.productID == productID.rawValue
            && transaction.appBundleID == appBundleIdentifier
            && transaction.productType == .consumable
            && transaction.reason == .purchase
            && transaction.revocationDate == nil
            && !transaction.isUpgraded
            && ownershipMatches(transaction)
            && transaction.purchaseDate.timeIntervalSince(purchasedAfter)
            >= -maximumClockSkew
    }

    private func ownershipMatches(_ transaction: Transaction) -> Bool {
        switch ownershipPolicy {
        case .appStoreAccount:
            true
        case let .appAccountToken(expectedToken):
            transaction.appAccountToken == expectedToken
        }
    }
}
