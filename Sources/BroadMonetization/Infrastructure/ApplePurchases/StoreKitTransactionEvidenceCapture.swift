import StoreKit

enum StoreKitTransactionEvidenceCapture {
    static func capture(
        _ result: VerificationResult<Transaction>?
    ) -> CapturedStoreTransactionEvidence? {
        guard let result, case let .verified(transaction) = result else {
            return nil
        }
        return capture(transaction, signedTransaction: result.jwsRepresentation)
    }

    static func capture(
        _ transaction: Transaction,
        signedTransaction: String
    ) -> CapturedStoreTransactionEvidence {
        CapturedStoreTransactionEvidence(
            transactionID: String(transaction.id),
            productID: transaction.productID,
            signedTransaction: signedTransaction,
            purchasedAt: transaction.purchaseDate,
            appBundleIdentifier: transaction.appBundleID,
            appAccountToken: transaction.appAccountToken,
            isConsumable: transaction.productType == .consumable,
            isPurchase: transaction.reason == .purchase,
            revocationDate: transaction.revocationDate,
            isUpgraded: transaction.isUpgraded
        )
    }
}
