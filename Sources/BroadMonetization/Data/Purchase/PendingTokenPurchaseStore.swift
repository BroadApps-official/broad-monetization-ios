import BroadCore
import Foundation

/// Durable, one-at-a-time token purchase state. Production apps should use the
/// same encrypted/file-backed `CacheRepositoryProtocol` composition as the
/// rest of BroadCore; the store never owns the token balance.
public actor PendingTokenPurchaseStore: PendingTokenPurchaseStoreProtocol {
    public nonisolated let pendingOperationBlockerKey: PendingOperationBlockerKey

    private struct Record: Codable, Equatable, Sendable {
        let subjectKey: String
        let applicationIdentifier: String
        let analyticsContext: PurchaseAnalyticsContext
        let startedAt: Date
        let evidence: TokenTransactionEvidence?
    }

    private let cache: any CacheRepositoryProtocol
    private let key: CacheKey<Record>
    private let subjectKey: String
    private let applicationIdentifier: String
    private let clock: CacheClock
    private let diagnostics: KeychainPurchaseDiagnosticStore

    public init(
        subject: EntitlementSubject,
        applicationIdentifier: String,
        cache: any CacheRepositoryProtocol,
        retention: TimeInterval = 7 * 24 * 60 * 60,
        clock: CacheClock = .system
    ) {
        precondition(
            MonetizationIdentifierPolicy.isValid(applicationIdentifier),
            "Application identifier must be valid"
        )
        precondition(
            retention.isFinite && retention > 0,
            "Token purchase retention must be finite and positive"
        )
        let subjectKey = subject.cacheKeyComponent
        self.subjectKey = subjectKey
        self.applicationIdentifier = applicationIdentifier
        self.cache = cache
        self.clock = clock
        diagnostics = KeychainPurchaseDiagnosticStore(
            applicationIdentifier: applicationIdentifier,
            kind: .consumable
        )
        pendingOperationBlockerKey = PendingOperationBlockerKey(
            kind: .tokenPurchase,
            applicationIdentifier: applicationIdentifier
        )
        key = CacheKey(
            name: "pending-token-purchase-\(applicationIdentifier)",
            schemaIdentifier: "dev.broadapps.monetization.pending-token-purchase",
            version: 1,
            policy: CachePolicy(
                timeToLive: retention,
                corruptedEntryAction: .preserve,
                schemaMismatchAction: .preserve,
                versionMismatchAction: .preserve
            )
        )
    }

    public func begin(context: PurchaseAnalyticsContext) async -> Bool {
        let startedAt = clock.now()
        guard startedAt.timeIntervalSinceReferenceDate.isFinite else {
            return false
        }
        do {
            let inserted = try await cache.insertIfMissing(
                Record(
                    subjectKey: subjectKey,
                    applicationIdentifier: applicationIdentifier,
                    analyticsContext: context,
                    startedAt: startedAt,
                    evidence: nil
                ),
                for: key
            )
            if inserted {
                await diagnostics.begin(
                    context: context,
                    kind: .consumable,
                    startedAt: startedAt
                )
            }
            return inserted
        } catch {
            return false
        }
    }

    public func state() async -> PendingTokenPurchaseState {
        guard let record = await readRecord() else {
            do {
                let result: CacheReadResult<Record> = try await cache.read(key)
                if case .missing(.notFound) = result {
                    return .none
                }
            } catch {}
            return .unavailable
        }
        guard record.applicationIdentifier == applicationIdentifier else {
            return .unavailable
        }
        return .pending(
            PendingTokenPurchaseIntent(
                analyticsContext: record.analyticsContext,
                startedAt: record.startedAt,
                evidence: record.evidence,
                belongsToCurrentSubject: record.subjectKey == subjectKey
            )
        )
    }

    public func save(
        evidence: TokenTransactionEvidence,
        attemptID: MonetizationAttemptID
    ) async -> Bool {
        guard let record = await readRecord(),
              record.applicationIdentifier == applicationIdentifier,
              record.analyticsContext.attemptID == attemptID,
              record.analyticsContext.productID == evidence.productID
        else {
            return false
        }
        let updated = Record(
            subjectKey: record.subjectKey,
            applicationIdentifier: record.applicationIdentifier,
            analyticsContext: record.analyticsContext,
            startedAt: record.startedAt,
            evidence: evidence
        )
        do {
            let replaced = try await cache.replace(updated, ifMatching: record, for: key)
            if replaced {
                await diagnostics.note(
                    attemptID: attemptID,
                    stage: .transactionVerified,
                    diagnosticCode: nil
                )
            }
            return replaced
        } catch {
            return false
        }
    }

    public func clear(attemptID: MonetizationAttemptID) async -> Bool {
        guard let record = await readRecord(),
              record.applicationIdentifier == applicationIdentifier,
              record.analyticsContext.attemptID == attemptID
        else {
            return false
        }
        do {
            let removed = try await cache.remove(key, ifMatching: record)
            if removed {
                await diagnostics.clear(attemptID: attemptID)
            }
            return removed
        } catch {
            return false
        }
    }

    public func noteDiagnostic(
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
                kind: .consumable,
                startedAt: intent.startedAt
            )
        }
        await diagnostics.note(
            attemptID: attemptID,
            stage: stage,
            diagnosticCode: diagnosticCode
        )
    }

    public func diagnosticSnapshot() async -> PendingPurchaseDiagnostic? {
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
                kind: .consumable,
                startedAt: intent.startedAt,
                lastCheckedAt: matching?.lastCheckedAt,
                stage: matching?.stage ?? (intent.evidence == nil ? .started : .transactionVerified),
                diagnosticCode: matching?.diagnosticCode,
                isPendingLocally: true,
                reviewRequired: false
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

    private func readRecord() async -> Record? {
        do {
            let result: CacheReadResult<Record> = try await cache.read(key)
            switch result {
            case let .fresh(envelope), let .stale(envelope):
                return envelope.value
            case .missing:
                return nil
            }
        } catch {
            return nil
        }
    }
}

/// Explicit fixture adapter. Production compositions use
/// `PendingTokenPurchaseStore` so a process termination cannot duplicate a
/// charge or lose backend fulfillment.
public actor InMemoryPendingTokenPurchaseStore:
    PendingTokenPurchaseStoreProtocol {
    public nonisolated let pendingOperationBlockerKey: PendingOperationBlockerKey
    private var intent: PendingTokenPurchaseIntent?

    public init(applicationIdentifier: String = "dev.broadapps.fixture") {
        pendingOperationBlockerKey = PendingOperationBlockerKey(
            kind: .tokenPurchase,
            applicationIdentifier: applicationIdentifier
        )
    }

    public func begin(context: PurchaseAnalyticsContext) -> Bool {
        intent = PendingTokenPurchaseIntent(
            analyticsContext: context,
            startedAt: Date(),
            evidence: nil,
            belongsToCurrentSubject: true
        )
        return true
    }

    public func state() -> PendingTokenPurchaseState {
        intent.map(PendingTokenPurchaseState.pending) ?? .none
    }

    public func save(
        evidence: TokenTransactionEvidence,
        attemptID: MonetizationAttemptID
    ) -> Bool {
        guard let current = intent, current.attemptID == attemptID else {
            return false
        }
        intent = PendingTokenPurchaseIntent(
            analyticsContext: current.analyticsContext,
            startedAt: current.startedAt,
            evidence: evidence,
            belongsToCurrentSubject: current.belongsToCurrentSubject
        )
        return true
    }

    public func clear(attemptID: MonetizationAttemptID) -> Bool {
        guard intent?.attemptID == attemptID else {
            return false
        }
        intent = nil
        return true
    }
}
