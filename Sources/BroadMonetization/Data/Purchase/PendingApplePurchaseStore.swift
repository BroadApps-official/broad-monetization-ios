import BroadCore
import Foundation

public actor PendingApplePurchaseStore: PendingApplePurchaseStoreProtocol {
    public nonisolated let pendingOperationBlockerKey: PendingOperationBlockerKey

    private struct Record: Codable, Equatable, Sendable {
        let subjectKey: String
        let applicationIdentifier: String
        let analyticsContext: PurchaseAnalyticsContext
        let productKind: MonetizationProductKind
        let startedAt: Date
        let reviewAfter: Date
        let phase: PendingApplePurchaseIntent.Phase

        init(
            subjectKey: String,
            applicationIdentifier: String,
            analyticsContext: PurchaseAnalyticsContext,
            productKind: MonetizationProductKind,
            startedAt: Date,
            reviewAfter: Date,
            phase: PendingApplePurchaseIntent.Phase
        ) {
            precondition(
                MonetizationIdentifierPolicy.isValid(subjectKey),
                "Pending Apple purchase subject key must be valid"
            )
            precondition(
                MonetizationIdentifierPolicy.isValid(applicationIdentifier),
                "Pending Apple purchase application identifier must be valid"
            )
            precondition(
                startedAt.timeIntervalSinceReferenceDate.isFinite,
                "Pending Apple purchase start date must be finite"
            )
            precondition(
                reviewAfter.timeIntervalSinceReferenceDate.isFinite && reviewAfter >= startedAt,
                "Pending Apple purchase review date must be finite and ordered"
            )

            self.subjectKey = subjectKey
            self.applicationIdentifier = applicationIdentifier
            self.analyticsContext = analyticsContext
            self.productKind = productKind
            self.startedAt = startedAt
            self.reviewAfter = reviewAfter
            self.phase = phase
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let subjectKey = try container.decode(String.self, forKey: .subjectKey)
            let applicationIdentifier = try container.decode(
                String.self,
                forKey: .applicationIdentifier
            )
            let analyticsContext = try container.decode(
                PurchaseAnalyticsContext.self,
                forKey: .analyticsContext
            )
            let productKind = try container.decode(
                MonetizationProductKind.self,
                forKey: .productKind
            )
            let startedAt = try container.decode(Date.self, forKey: .startedAt)
            let reviewAfter = try container.decode(Date.self, forKey: .reviewAfter)
            let phase = try container.decode(
                PendingApplePurchaseIntent.Phase.self,
                forKey: .phase
            )

            guard MonetizationIdentifierPolicy.isValid(subjectKey),
                  MonetizationIdentifierPolicy.isValid(applicationIdentifier),
                  MonetizationIdentifierPolicy.isValid(analyticsContext.attemptID.rawValue),
                  MonetizationIdentifierPolicy.isValid(analyticsContext.productID.rawValue),
                  startedAt.timeIntervalSinceReferenceDate.isFinite,
                  reviewAfter.timeIntervalSinceReferenceDate.isFinite,
                  reviewAfter >= startedAt
            else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "Invalid persisted Apple purchase intent"
                    )
                )
            }

            self.init(
                subjectKey: subjectKey,
                applicationIdentifier: applicationIdentifier,
                analyticsContext: analyticsContext,
                productKind: productKind,
                startedAt: startedAt,
                reviewAfter: reviewAfter,
                phase: phase
            )
        }
    }

    private let cache: any CacheRepositoryProtocol
    private let key: CacheKey<Record>
    private let subjectKey: String
    private let applicationIdentifier: String
    private let reviewInterval: TimeInterval
    private let clock: CacheClock

    public init(
        subject: EntitlementSubject,
        applicationIdentifier: String,
        cache: any CacheRepositoryProtocol,
        reviewInterval: TimeInterval = 24 * 60 * 60,
        clock: CacheClock = .system
    ) {
        precondition(
            MonetizationIdentifierPolicy.isValid(applicationIdentifier),
            "Application identifier must be valid"
        )
        precondition(
            reviewInterval.isFinite && reviewInterval > 0,
            "Pending Apple purchase review interval must be finite and positive"
        )

        let subjectKey = subject.cacheKeyComponent
        self.subjectKey = subjectKey
        self.applicationIdentifier = applicationIdentifier
        pendingOperationBlockerKey = PendingOperationBlockerKey(
            kind: .applePurchase,
            applicationIdentifier: applicationIdentifier
        )
        self.reviewInterval = reviewInterval
        self.clock = clock
        self.cache = cache
        key = CacheKey(
            // One app-wide key intentionally survives host login/logout. The
            // record retains its originating subject so only that identity can
            // perform user-confirmed abandonment/reconciliation.
            name: "pending-apple-purchase-\(applicationIdentifier)",
            schemaIdentifier: "dev.broadapps.monetization.pending-apple-purchase",
            version: 1,
            policy: CachePolicy(
                timeToLive: reviewInterval,
                corruptedEntryAction: .preserve,
                schemaMismatchAction: .preserve,
                versionMismatchAction: .preserve
            )
        )
    }

    public func begin(
        context: PurchaseAnalyticsContext,
        productKind: MonetizationProductKind
    ) async -> Bool {
        let startedAt = clock.now()
        let reviewTimestamp = startedAt.timeIntervalSinceReferenceDate + reviewInterval
        guard startedAt.timeIntervalSinceReferenceDate.isFinite,
              reviewTimestamp.isFinite
        else {
            return false
        }

        let record = Record(
            subjectKey: subjectKey,
            applicationIdentifier: applicationIdentifier,
            analyticsContext: context,
            productKind: productKind,
            startedAt: startedAt,
            reviewAfter: Date(timeIntervalSinceReferenceDate: reviewTimestamp),
            phase: .initiated
        )

        do {
            return try await cache.insertIfMissing(record, for: key)
        } catch {
            return false
        }
    }

    public func state() async -> PendingApplePurchaseState {
        let result: CacheReadResult<Record>
        do {
            result = try await cache.read(key)
        } catch {
            return .unavailable
        }

        switch result {
        case let .fresh(envelope), let .stale(envelope):
            let record = envelope.value
            guard record.applicationIdentifier == applicationIdentifier
            else {
                return .unavailable
            }
            return .pending(
                PendingApplePurchaseIntent(
                    analyticsContext: record.analyticsContext,
                    productKind: record.productKind,
                    startedAt: record.startedAt,
                    reviewRequired: record.reviewAfter <= clock.now(),
                    belongsToCurrentSubject: record.subjectKey == subjectKey,
                    phase: record.phase
                )
            )
        case .missing(.notFound):
            return .none
        case .missing:
            return .unavailable
        }
    }

    public func markTransactionConfirmed(
        attemptID: MonetizationAttemptID
    ) async -> Bool {
        let result: CacheReadResult<Record>
        do {
            result = try await cache.read(key)
        } catch {
            return false
        }

        let record: Record
        switch result {
        case let .fresh(envelope), let .stale(envelope):
            record = envelope.value
        case .missing:
            return false
        }
        guard record.applicationIdentifier == applicationIdentifier,
              record.analyticsContext.attemptID == attemptID
        else {
            return false
        }

        let confirmed = Record(
            subjectKey: record.subjectKey,
            applicationIdentifier: record.applicationIdentifier,
            analyticsContext: record.analyticsContext,
            productKind: record.productKind,
            startedAt: record.startedAt,
            reviewAfter: record.reviewAfter,
            phase: .transactionConfirmed
        )
        do {
            return try await cache.replace(
                confirmed,
                ifMatching: record,
                for: key
            )
        } catch {
            return false
        }
    }
}

public extension PendingApplePurchaseStore {
    func clear(attemptID: MonetizationAttemptID) async -> Bool {
        let result: CacheReadResult<Record>
        do {
            result = try await cache.read(key)
        } catch {
            return false
        }
        let record: Record
        switch result {
        case let .fresh(envelope), let .stale(envelope):
            record = envelope.value
        case .missing:
            return false
        }
        guard record.analyticsContext.attemptID == attemptID,
              record.applicationIdentifier == applicationIdentifier
        else {
            return false
        }
        do {
            return try await cache.remove(key, ifMatching: record)
        } catch {
            return false
        }
    }
}

/// Explicit non-durable adapter for local fixtures. Production compositions use
/// `PendingApplePurchaseStore` so process termination cannot drop the blocker.
public actor InMemoryPendingApplePurchaseStore: PendingApplePurchaseStoreProtocol {
    public nonisolated let pendingOperationBlockerKey: PendingOperationBlockerKey
    private var intent: PendingApplePurchaseIntent?

    public init(
        applicationIdentifier: String = "dev.broadapps.fixture"
    ) {
        pendingOperationBlockerKey = PendingOperationBlockerKey(
            kind: .applePurchase,
            applicationIdentifier: applicationIdentifier
        )
    }

    public func begin(
        context: PurchaseAnalyticsContext,
        productKind: MonetizationProductKind
    ) -> Bool {
        intent = PendingApplePurchaseIntent(
            analyticsContext: context,
            productKind: productKind,
            startedAt: Date(),
            reviewRequired: false,
            belongsToCurrentSubject: true,
            phase: .initiated
        )
        return true
    }

    public func state() -> PendingApplePurchaseState {
        intent.map(PendingApplePurchaseState.pending) ?? .none
    }

    public func clear(attemptID: MonetizationAttemptID) -> Bool {
        guard intent?.attemptID == attemptID else {
            return false
        }
        intent = nil
        return true
    }

    public func markTransactionConfirmed(
        attemptID: MonetizationAttemptID
    ) -> Bool {
        guard let current = intent,
              current.attemptID == attemptID
        else {
            return false
        }
        intent = PendingApplePurchaseIntent(
            analyticsContext: current.analyticsContext,
            productKind: current.productKind,
            startedAt: current.startedAt,
            reviewRequired: current.reviewRequired,
            belongsToCurrentSubject: current.belongsToCurrentSubject,
            phase: .transactionConfirmed
        )
        return true
    }
}
