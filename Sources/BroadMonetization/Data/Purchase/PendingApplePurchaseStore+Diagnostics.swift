import Foundation

public extension PendingApplePurchaseStore {
    func noteDiagnostic(
        attemptID: MonetizationAttemptID,
        stage: PendingPurchaseDiagnostic.Stage,
        diagnosticCode: String? = nil
    ) async {
        guard case let .pending(intent) = await state(), intent.attemptID == attemptID else {
            return
        }
        if case .missing = await diagnostics.read() {
            await diagnostics.begin(
                context: intent.analyticsContext,
                kind: intent.productKind == .consumable ? .consumable : .premium,
                startedAt: intent.startedAt
            )
        }
        await diagnostics.note(
            attemptID: attemptID,
            stage: stage,
            diagnosticCode: diagnosticCode
        )
    }

    /// Returns support context even when a reinstall removed the local intent.
    /// A Keychain-only record must never be used to grant access or unblock a
    /// payment: the host must reconcile it with StoreKit and its own backend.
    func diagnosticSnapshot() async -> PendingPurchaseDiagnostic? {
        let current = await state()
        let saved = await diagnostics.read()
        let keychainRecord: KeychainPurchaseDiagnosticStore.Record? = switch saved {
        case let .value(record): record
        case .missing, .unavailable: nil
        }
        switch current {
        case let .pending(intent):
            let matching = keychainRecord?.attemptID == intent.attemptID
                ? keychainRecord : nil
            return PendingPurchaseDiagnostic(
                attemptID: intent.attemptID,
                productID: intent.productID,
                requestedPlacementID: intent.analyticsContext.requestedPlacementID,
                resolvedPlacementID: intent.analyticsContext.resolvedPlacementID,
                paywallVariationID: intent.analyticsContext.paywallVariationID,
                kind: intent.productKind == .consumable ? .consumable : .premium,
                startedAt: intent.startedAt,
                lastCheckedAt: matching?.lastCheckedAt,
                stage: matching?.stage ?? (intent.phase == .transactionConfirmed
                    ? .transactionVerified : .started),
                diagnosticCode: matching?.diagnosticCode,
                isPendingLocally: true,
                reviewRequired: intent.reviewRequired
            )
        case .none, .unavailable:
            guard let record = keychainRecord else { return nil }
            return PendingPurchaseDiagnostic(
                attemptID: record.attemptID,
                productID: record.analyticsContext.productID,
                requestedPlacementID: record.analyticsContext.requestedPlacementID,
                resolvedPlacementID: record.analyticsContext.resolvedPlacementID,
                paywallVariationID: record.analyticsContext.paywallVariationID,
                kind: record.kind,
                startedAt: record.startedAt,
                lastCheckedAt: record.lastCheckedAt,
                stage: current == .unavailable ? .localStoreUnavailable : .localRecordMissing,
                diagnosticCode: record.diagnosticCode,
                isPendingLocally: false,
                reviewRequired: false
            )
        }
    }
}
