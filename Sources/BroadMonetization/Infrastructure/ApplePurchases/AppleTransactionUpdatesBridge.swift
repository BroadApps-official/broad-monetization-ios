import Foundation
import StoreKit

/// The single process-wide `Transaction.updates` listener.
///
/// It forwards only JWS-verified transactions of the host bundle with reason
/// `.purchase`, without revocation or upgrade, and under the same ownership policy
/// the entitlement check uses, to a ``PendingApplePurchaseCoordinator``. It
/// deliberately **never calls** `transaction.finish()`: the purchase provider owns
/// finishing.
///
/// Install one, once, before the provider SDK starts, so a purchase that completes
/// out of band (a cold-launch approval, an Ask-to-Buy result) is not lost. There
/// must be exactly one `Transaction.updates` listener in the process.
public actor AppleTransactionUpdatesBridge {
    private let appBundleIdentifier: String
    private var coordinator: PendingApplePurchaseCoordinator?
    private var ownershipPolicy: StoreKitEntitlementOwnershipPolicy?
    private var updatesTask: Task<Void, Never>?

    public init(appBundleIdentifier: String) {
        let trimmed = appBundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        precondition(
            !trimmed.isEmpty && trimmed == appBundleIdentifier,
            "App bundle identifier must be nonempty and contain no surrounding whitespace"
        )
        self.appBundleIdentifier = appBundleIdentifier
    }

    public func install(
        _ coordinator: PendingApplePurchaseCoordinator?,
        ownershipPolicy: StoreKitEntitlementOwnershipPolicy
    ) {
        self.coordinator = coordinator
        self.ownershipPolicy = ownershipPolicy
        startIfNeeded()
    }

    private func startIfNeeded() {
        guard updatesTask == nil else {
            return
        }

        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard case let .verified(transaction) = result else {
                    continue
                }
                await self?.receive(transaction)
            }
        }
    }

    private func receive(_ transaction: Transaction) async {
        guard transaction.appBundleID == appBundleIdentifier,
              transaction.reason == .purchase,
              transaction.revocationDate == nil,
              !transaction.isUpgraded,
              let ownershipPolicy
        else {
            return
        }

        if case let .appAccountToken(expected) = ownershipPolicy,
           transaction.appAccountToken != expected {
            return
        }

        _ = await coordinator?.verifiedTransactionUpdated(
            VerifiedApplePurchaseTransaction(
                productID: ProductID(rawValue: transaction.productID),
                purchaseDate: transaction.purchaseDate,
                reason: .purchase
            )
        )
    }
}
