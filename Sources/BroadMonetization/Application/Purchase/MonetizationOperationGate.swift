import Foundation

public struct MonetizationOperationKind: RawRepresentable, Codable, Hashable, Sendable, ValidatedMonetizationIdentifier {
    public let rawValue: String
    public init(rawValue: String) {
        precondition(MonetizationIdentifierPolicy.isValid(rawValue))
        self.rawValue = rawValue
    }

    public static let purchase = Self(rawValue: "purchase")
    public static let tokenPurchase = Self(rawValue: "token-purchase")
    public static let restore = Self(rawValue: "restore")
}

public struct MonetizationOperationLease: Equatable, Sendable {
    fileprivate let id: UUID
    public let kind: MonetizationOperationKind
}

/// Reports whether a durable monetization operation is still pending. The gate
/// owns no persistence details and can therefore coordinate Apple and external
/// payment adapters without reversing their dependencies.
public protocol PendingOperationBlockerProtocol: Sendable {
    /// Stable application-wide identity of the durable blocker. Registering a
    /// newly composed store with the same key replaces the previous identity-
    /// scoped instance instead of retaining it forever.
    nonisolated var pendingOperationBlockerKey: PendingOperationBlockerKey { get }

    func hasPendingMonetizationOperation() async -> Bool
}

public struct PendingOperationBlockerKey: Hashable, Sendable {
    public struct Kind: RawRepresentable, Codable, Hashable, Sendable, ValidatedMonetizationIdentifier {
        public let rawValue: String
        public init(rawValue: String) {
            precondition(MonetizationIdentifierPolicy.isValid(rawValue))
            self.rawValue = rawValue
        }

        public static let applePurchase = Self(rawValue: "apple-purchase")
        public static let tokenPurchase = Self(rawValue: "token-purchase")
    }

    public let kind: Kind
    public let applicationIdentifier: String

    public init(kind: Kind, applicationIdentifier: String) {
        precondition(
            MonetizationIdentifierPolicy.isValid(applicationIdentifier),
            "Pending operation application identifier must be valid"
        )
        self.kind = kind
        self.applicationIdentifier = applicationIdentifier
    }
}

/// One application-wide gate shared by every payment and restore entry point.
/// It protects direct callers and multiple paywall view models, not only one
/// screen's busy state. Each provider decides whether its durable operation
/// remains blocking after a short-lived SDK/browser lease is released.
public actor MonetizationOperationGate {
    private nonisolated let blockerRegistry = PendingOperationBlockerRegistry()
    private var activeLease: MonetizationOperationLease?
    private var statusContinuations: [UUID: AsyncStream<Void>.Continuation] = [:]

    public init() {}

    /// Registration is synchronous so an already persisted checkout is visible
    /// before a newly assembled purchase or restore service can be called.
    public nonisolated func registerPendingOperationBlocker(
        _ blocker: any PendingOperationBlockerProtocol
    ) {
        blockerRegistry.register(
            blocker,
            for: blocker.pendingOperationBlockerKey
        )
        Task {
            await self.notifyFinancialOperationStateChanged()
        }
    }

    /// Emits once on subscription and whenever a lease or durable pending
    /// state may have changed. Events are coalesced; consumers re-read status.
    public func financialOperationStatusChanges() -> AsyncStream<Void> {
        let observerID = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            statusContinuations[observerID] = continuation
            continuation.yield()
            continuation.onTermination = { [weak self] _ in
                Task {
                    await self?.removeStatusContinuation(observerID)
                }
            }
        }
    }

    /// Coordinators call this after an out-of-band StoreKit/backend terminal
    /// result mutates durable pending state.
    public func notifyFinancialOperationStateChanged() {
        for continuation in statusContinuations.values {
            continuation.yield()
        }
    }

    public func acquire(
        _ kind: MonetizationOperationKind
    ) async -> MonetizationOperationLease? {
        guard activeLease == nil else {
            return nil
        }

        let lease = MonetizationOperationLease(id: UUID(), kind: kind)
        activeLease = lease
        notifyFinancialOperationStateChanged()

        for blocker in blockerRegistry.current() {
            guard await !(blocker.hasPendingMonetizationOperation()) else {
                if activeLease == lease {
                    activeLease = nil
                    notifyFinancialOperationStateChanged()
                }
                return nil
            }
        }

        return lease
    }

    public func release(_ lease: MonetizationOperationLease) {
        guard activeLease == lease else {
            return
        }

        activeLease = nil
        notifyFinancialOperationStateChanged()
    }

    public func isFinancialOperationBlocked() async -> Bool {
        guard activeLease == nil else {
            return true
        }
        for blocker in blockerRegistry.current() {
            guard await !(blocker.hasPendingMonetizationOperation()) else {
                return true
            }
        }
        return false
    }

    private func removeStatusContinuation(_ observerID: UUID) {
        statusContinuations.removeValue(forKey: observerID)
    }
}

public protocol MonetizationOperationGateProviding: Sendable {
    var monetizationOperationGate: MonetizationOperationGate { get }
}

private final class PendingOperationBlockerRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var blockers: [
        PendingOperationBlockerKey: any PendingOperationBlockerProtocol
    ] = [:]

    func register(
        _ blocker: any PendingOperationBlockerProtocol,
        for key: PendingOperationBlockerKey
    ) {
        lock.lock()
        blockers[key] = blocker
        lock.unlock()
    }

    func current() -> [any PendingOperationBlockerProtocol] {
        lock.lock()
        let blockers = Array(blockers.values)
        lock.unlock()
        return blockers
    }
}
