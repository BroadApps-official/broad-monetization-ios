import BroadCore
import Foundation

public enum PendingRUCheckoutState: Equatable, Sendable {
    case none
    case pending(PendingRUCheckoutContext)
    /// Account-policy polling ended. The last attempt remains available for
    /// reconciliation, but no longer blocks another financial operation.
    case awaitingReconciliation(PendingRUCheckoutContext)
    /// An app-wide financial blocker exists for another identity. Its backend
    /// session and attempt identifiers are deliberately not disclosed.
    case blockedByAnotherSubject
    case unavailable
}

public protocol PendingRUCheckoutStoreProtocol: PendingOperationBlockerProtocol {
    func state() async -> PendingRUCheckoutState
    func save(_ context: PendingRUCheckoutContext) async -> Bool
    func clear(
        checkoutSessionID: CheckoutSessionID,
        attemptID: MonetizationAttemptID
    ) async -> Bool
    /// Releases only the matching account-policy attempt's local waiting state.
    /// This does not cancel the payment or prove that its URL has expired.
    func finishWaiting(
        checkoutSessionID: CheckoutSessionID,
        attemptID: MonetizationAttemptID
    ) async -> Bool
}

public extension PendingRUCheckoutStoreProtocol {
    /// Custom stores must implement durable, compare-and-replace semantics to
    /// support account-policy retries. Older stores retain their blocker.
    func finishWaiting(
        checkoutSessionID _: CheckoutSessionID,
        attemptID _: MonetizationAttemptID
    ) async -> Bool {
        false
    }
}

public actor PendingRUCheckoutStore: PendingRUCheckoutStoreProtocol {
    public nonisolated let pendingOperationBlockerKey: PendingOperationBlockerKey

    private struct Record: Codable, Equatable, Sendable {
        let subjectKey: String
        let applicationIdentifier: String
        let context: PendingRUCheckoutContext
        let waitingCompleted: Bool

        var isReconciliationOnly: Bool {
            waitingCompleted && context.accountExpectation != nil
        }

        init(
            subjectKey: String,
            applicationIdentifier: String,
            context: PendingRUCheckoutContext,
            waitingCompleted: Bool = false
        ) {
            precondition(
                MonetizationIdentifierPolicy.isValid(subjectKey)
                    && MonetizationIdentifierPolicy.isValid(applicationIdentifier),
                "Pending RU checkout scope must be valid"
            )
            self.subjectKey = subjectKey
            self.applicationIdentifier = applicationIdentifier
            self.context = context
            self.waitingCompleted = waitingCompleted
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let subjectKey = try container.decode(String.self, forKey: .subjectKey)
            let applicationIdentifier = try container.decode(
                String.self,
                forKey: .applicationIdentifier
            )
            guard MonetizationIdentifierPolicy.isValid(subjectKey),
                  MonetizationIdentifierPolicy.isValid(applicationIdentifier)
            else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "Invalid persisted RU checkout scope"
                    )
                )
            }
            try self.init(
                subjectKey: subjectKey,
                applicationIdentifier: applicationIdentifier,
                context: container.decode(
                    PendingRUCheckoutContext.self,
                    forKey: .context
                ),
                waitingCompleted: container.decodeIfPresent(Bool.self, forKey: .waitingCompleted) ?? false
            )
        }
    }

    private let cache: any CacheRepositoryProtocol
    private let key: CacheKey<Record>
    private let subjectKey: String
    private let applicationIdentifier: String
    private let authorizationBinding: SubjectAuthorizationBinding
    private let clock: CacheClock

    public init(
        subject: EntitlementSubject,
        applicationIdentifier: String,
        authorizationBinding: SubjectAuthorizationBinding,
        cache: any CacheRepositoryProtocol,
        retention: TimeInterval = 24 * 60 * 60,
        clock: CacheClock = .system
    ) {
        precondition(retention.isFinite && retention > 0, "Pending checkout retention must be finite and positive")
        precondition(
            MonetizationIdentifierPolicy.isValid(applicationIdentifier),
            "Application identifier must be valid"
        )
        precondition(
            authorizationBinding.subject == subject,
            "Pending RU checkout binding must match the exact subject"
        )
        self.cache = cache
        subjectKey = subject.cacheKeyComponent
        self.applicationIdentifier = applicationIdentifier
        self.authorizationBinding = authorizationBinding
        pendingOperationBlockerKey = PendingOperationBlockerKey(
            kind: .ruCheckout,
            applicationIdentifier: applicationIdentifier
        )
        key = CacheKey(
            // One app-wide key blocks a second Apple/RU charge across host
            // login/logout. The record retains the originating subject so a
            // different identity never polls its backend session.
            name: "pending-ru-checkout-\(applicationIdentifier)",
            schemaIdentifier: "dev.broadapps.monetization.pending-ru-checkout",
            version: 1,
            policy: CachePolicy(
                timeToLive: retention,
                corruptedEntryAction: .preserve,
                schemaMismatchAction: .preserve,
                versionMismatchAction: .preserve
            )
        )
        self.clock = clock
    }

    /// Storage failure is treated as potentially pending. Starting another
    /// payment is less safe than temporarily declining checkout/restore when a
    /// durable financial state cannot be inspected.
    public func hasPendingMonetizationOperation() async -> Bool {
        switch await state() {
        case .pending, .blockedByAnotherSubject, .unavailable:
            true
        case .none, .awaitingReconciliation:
            false
        }
    }

    public func save(_ context: PendingRUCheckoutContext) async -> Bool {
        guard authorizationBinding.isCurrent(),
              context.expiresAt.map({ $0 > clock.now() }) ?? true
        else {
            return false
        }
        do {
            let replacement = Record(
                subjectKey: subjectKey,
                applicationIdentifier: applicationIdentifier,
                context: context
            )
            if let previous = try await currentRecord(requireSameSubject: false), previous.isReconciliationOnly,
               context.accountExpectation != nil {
                let replaced = try await cache.replace(replacement, ifMatching: previous, for: key)
                return replaced && authorizationBinding.isCurrent()
            }
            let inserted = try await cache.insertIfMissing(
                replacement,
                for: key
            )
            return inserted && authorizationBinding.isCurrent()
        } catch {
            return false
        }
    }

    public func clear(
        checkoutSessionID: CheckoutSessionID,
        attemptID: MonetizationAttemptID
    ) async -> Bool {
        guard authorizationBinding.isCurrent() else {
            return false
        }
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
              record.subjectKey == subjectKey,
              authorizationBinding.isCurrent(),
              record.context.checkoutSessionID == checkoutSessionID,
              record.context.attemptID == attemptID
        else {
            return false
        }
        do {
            let removed = try await cache.remove(key, ifMatching: record)
            guard removed else {
                return false
            }
            guard authorizationBinding.isCurrent() else {
                // Identity changed while compare-and-remove was suspended. Put
                // the exact old blocker back unless another attempt already won.
                _ = try? await cache.insertIfMissing(record, for: key)
                return false
            }
            return true
        } catch {
            return false
        }
    }

    public func state() async -> PendingRUCheckoutState {
        guard authorizationBinding.isCurrent() else {
            return .unavailable
        }
        let result: CacheReadResult<Record>
        do {
            result = try await cache.read(key)
        } catch {
            return .unavailable
        }

        let record: Record
        switch result {
        case let .fresh(envelope), let .stale(envelope):
            record = envelope.value
        case .missing(.notFound):
            return .none
        case .missing:
            return .unavailable
        }
        guard authorizationBinding.isCurrent(),
              record.applicationIdentifier == applicationIdentifier
        else {
            return .unavailable
        }
        guard record.subjectKey == subjectKey else {
            return record.isReconciliationOnly ? .none : .blockedByAnotherSubject
        }

        // A completed wait is not a terminal payment status. Keep the latest
        // attempt for account reconciliation until a new checkout replaces it.
        return record.isReconciliationOnly
            ? .awaitingReconciliation(record.context) : .pending(record.context)
    }

    public func finishWaiting(
        checkoutSessionID: CheckoutSessionID,
        attemptID: MonetizationAttemptID
    ) async -> Bool {
        do {
            guard let record = try await currentRecord(),
                  record.context.accountExpectation != nil,
                  record.context.checkoutSessionID == checkoutSessionID,
                  record.context.attemptID == attemptID else { return false }
            if record.waitingCompleted {
                return true
            }
            let replacement = Record(
                subjectKey: subjectKey, applicationIdentifier: applicationIdentifier,
                context: record.context, waitingCompleted: true
            )
            let replaced = try await cache.replace(replacement, ifMatching: record, for: key)
            guard replaced else { return false }
            guard authorizationBinding.isCurrent() else {
                _ = try? await cache.replace(record, ifMatching: replacement, for: key)
                return false
            }
            return true
        } catch {
            return false
        }
    }

    private func currentRecord(requireSameSubject: Bool = true) async throws -> Record? {
        guard authorizationBinding.isCurrent() else { return nil }
        let result = try await cache.read(key)
        guard authorizationBinding.isCurrent() else { return nil }
        switch result {
        case let .fresh(envelope), let .stale(envelope):
            let record = envelope.value
            guard !requireSameSubject || record.subjectKey == subjectKey,
                  record.applicationIdentifier == applicationIdentifier else { return nil }
            return record
        case .missing:
            return nil
        }
    }
}
