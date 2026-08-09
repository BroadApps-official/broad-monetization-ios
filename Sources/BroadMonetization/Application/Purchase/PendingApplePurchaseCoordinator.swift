import Foundation

public enum PendingApplePurchaseOutcome: Equatable, Sendable {
    case noPendingPurchase
    case activated(EntitlementSnapshot)
    case transactionConfirmedAwaitingEntitlement(EntitlementSnapshot?)
    case consumableConfirmed
    case pending(PendingApplePurchaseIntent)
    case unavailable
}

/// Reconciles the one application-wide Apple purchase intent. A generic active
/// entitlement never proves that the attempted SKU completed. The coordinator
/// accepts only a verified StoreKit purchase for the exact SKU and keeps a
/// second durable `transactionConfirmed` phase until premium is authoritative.
public actor PendingApplePurchaseCoordinator {
    private let store: any PendingApplePurchaseStoreProtocol
    private let refreshEntitlement: any EntitlementRepositoryProtocol
    private let transactionRecovery: any PendingAppleTransactionRecoveryProtocol
    private let analytics: any MonetizationAnalyticsProtocol
    private let operationGate: MonetizationOperationGate
    private let maximumClockSkew: TimeInterval

    public init(
        store: any PendingApplePurchaseStoreProtocol,
        refreshEntitlement: any EntitlementRepositoryProtocol,
        transactionRecovery: any PendingAppleTransactionRecoveryProtocol,
        analytics: any MonetizationAnalyticsProtocol,
        operationGate: MonetizationOperationGate,
        maximumClockSkew: TimeInterval = 0
    ) {
        precondition(
            maximumClockSkew.isFinite && maximumClockSkew >= 0,
            "Apple transaction clock-skew tolerance must be finite and non-negative"
        )
        self.store = store
        self.refreshEntitlement = refreshEntitlement
        self.transactionRecovery = transactionRecovery
        self.analytics = NonBlockingMonetizationAnalytics.wrapping(analytics)
        self.operationGate = operationGate
        self.maximumClockSkew = maximumClockSkew
    }

    /// Call after launch and every transition to an active scene. It scans
    /// verified StoreKit history, so approvals completed before the live
    /// `Transaction.updates` listener started are not lost.
    public func applicationDidBecomeActive() async -> PendingApplePurchaseOutcome {
        switch await store.state() {
        case .none:
            .noPendingPurchase
        case .unavailable:
            .unavailable
        case let .pending(intent) where intent.phase == .transactionConfirmed:
            await reconcileConfirmed(intent)
        case let .pending(intent):
            switch await transactionRecovery.recover(intent) {
            case let .matched(transaction):
                await resolveVerified(transaction, intent: intent)
            case .noMatch:
                .pending(intent)
            case .unavailable:
                .unavailable
            }
        }
    }

    /// Forward only `.verified` StoreKit updates after checking the configured
    /// bundle/account ownership. The platform never finishes the transaction;
    /// Adapty or the host StoreKit adapter remains its sole owner.
    public func verifiedTransactionUpdated(
        _ transaction: VerifiedApplePurchaseTransaction
    ) async -> PendingApplePurchaseOutcome {
        switch await store.state() {
        case .none:
            return .noPendingPurchase
        case .unavailable:
            return .unavailable
        case let .pending(intent):
            guard matches(transaction, intent: intent) else {
                return .pending(intent)
            }
            return await resolveVerified(transaction, intent: intent)
        }
    }

    /// A user acknowledgement cannot cancel Ask-to-Buy or an outcome-unknown
    /// StoreKit operation. It therefore never clears the durable blocker. Hosts
    /// may use this hook to re-run reconciliation after showing support UI.
    @available(
        *,
        deprecated,
        message: "User acknowledgement cannot safely abandon a pending Apple charge"
    )
    public func abandonAfterUserConfirmation() async -> PendingApplePurchaseOutcome {
        await applicationDidBecomeActive()
    }
}

private extension PendingApplePurchaseCoordinator {
    func matches(
        _ transaction: VerifiedApplePurchaseTransaction,
        intent: PendingApplePurchaseIntent
    ) -> Bool {
        transaction.reason == .purchase
            && transaction.productID == intent.productID
            && transaction.purchaseDate.timeIntervalSince(intent.startedAt)
            >= -maximumClockSkew
    }

    func resolveVerified(
        _ transaction: VerifiedApplePurchaseTransaction,
        intent: PendingApplePurchaseIntent
    ) async -> PendingApplePurchaseOutcome {
        guard matches(transaction, intent: intent),
              await store.markTransactionConfirmed(attemptID: intent.attemptID)
        else {
            return .unavailable
        }

        if intent.productKind == .consumable {
            guard await store.clear(attemptID: intent.attemptID) else {
                return .unavailable
            }
            await operationGate.notifyFinancialOperationStateChanged()
            await analytics.track(.purchaseSuccess(intent.analyticsContext))
            return .consumableConfirmed
        }
        return await reconcileConfirmed(intent)
    }

    func reconcileConfirmed(
        _ intent: PendingApplePurchaseIntent
    ) async -> PendingApplePurchaseOutcome {
        guard intent.belongsToCurrentSubject else {
            await analytics.track(
                .purchaseCompletedButUnverified(intent.analyticsContext)
            )
            return .transactionConfirmedAwaitingEntitlement(nil)
        }

        let snapshot = await refreshEntitlement.refreshEntitlement(
            policy: .startNewGeneration
        )
        guard snapshot.isCurrentActiveConfirmed else {
            await analytics.track(
                .purchaseCompletedButUnverified(intent.analyticsContext)
            )
            return .transactionConfirmedAwaitingEntitlement(snapshot)
        }
        guard await store.clear(attemptID: intent.attemptID) else {
            return .unavailable
        }
        await operationGate.notifyFinancialOperationStateChanged()
        await analytics.track(.purchaseSuccess(intent.analyticsContext))
        return .activated(snapshot)
    }
}
