import Foundation
import StoreKit

/// Finds the verified consumable transaction after Adapty/StoreKit reports a
/// completed purchase. It does not finish transactions; the purchase adapter
/// remains their sole owner.
public struct StoreKitTokenTransactionEvidenceProvider:
    TokenTransactionEvidenceProviderProtocol,
    DirectTokenEvidenceProvider {
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

        for await result in Transaction.unfinished {
            guard !Task.isCancelled else {
                return .unavailable
            }
            switch evaluate(
                result,
                productID: productID,
                purchasedAfter: purchasedAfter
            ) {
            case let .verified(evidence):
                return .verified(evidence)
            case .relevantUnverified:
                foundRelevantUnverified = true
            case .irrelevant:
                break
            }
        }

        for await result in Transaction.all {
            guard !Task.isCancelled else {
                return .unavailable
            }
            switch evaluate(
                result,
                productID: productID,
                purchasedAfter: purchasedAfter
            ) {
            case let .verified(evidence):
                return .verified(evidence)
            case .relevantUnverified:
                foundRelevantUnverified = true
            case .irrelevant:
                break
            }
        }

        return foundRelevantUnverified ? .unavailable : .notFound
    }

    func evidence(
        from captured: CapturedStoreTransactionEvidence,
        productID: ProductID,
        purchasedAfter: Date
    ) async -> TokenEvidenceResolution {
        guard isRelevant(
            captured,
            productID: productID,
            purchasedAfter: purchasedAfter
        ) else {
            return .unavailable
        }
        return .verified(
            TokenTransactionEvidence(
                transactionID: captured.transactionID,
                productID: productID,
                signedTransaction: captured.signedTransaction,
                purchasedAt: captured.purchasedAt
            )
        )
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

    private func isRelevant(
        _ captured: CapturedStoreTransactionEvidence,
        productID: ProductID,
        purchasedAfter: Date
    ) -> Bool {
        captured.productID == productID.rawValue
            && captured.appBundleIdentifier == appBundleIdentifier
            && captured.isConsumable
            && captured.isPurchase
            && captured.revocationDate == nil
            && !captured.isUpgraded
            && ownershipMatches(captured.appAccountToken)
            && captured.purchasedAt.timeIntervalSince(purchasedAfter)
            >= -maximumClockSkew
    }

    private func ownershipMatches(_ transaction: Transaction) -> Bool {
        ownershipMatches(transaction.appAccountToken)
    }

    private func ownershipMatches(_ appAccountToken: UUID?) -> Bool {
        switch ownershipPolicy {
        case .appStoreAccount:
            true
        case let .appAccountToken(expectedToken):
            appAccountToken == expectedToken
        }
    }

    private func evaluate(
        _ result: VerificationResult<Transaction>,
        productID: ProductID,
        purchasedAfter: Date
    ) -> Evaluation {
        switch result {
        case let .unverified(transaction, _):
            return isRelevant(
                transaction,
                productID: productID,
                purchasedAfter: purchasedAfter
            ) ? .relevantUnverified : .irrelevant
        case let .verified(transaction):
            guard isRelevant(
                transaction,
                productID: productID,
                purchasedAfter: purchasedAfter
            ) else {
                return .irrelevant
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

    private enum Evaluation {
        case verified(TokenTransactionEvidence)
        case relevantUnverified
        case irrelevant
    }
}
