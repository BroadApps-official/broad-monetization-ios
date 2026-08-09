import Foundation

/// Public, non-sensitive description of the one durable Apple purchase intent.
/// The storage key is application-wide; `belongsToCurrentSubject` prevents a
/// newly assembled identity from reconciling another subject's intent with the
/// wrong entitlement repository while still blocking a second charge.
public struct PendingApplePurchaseIntent: Equatable, Sendable {
    public enum Phase: String, Codable, Equatable, Sendable {
        case initiated
        case transactionConfirmed = "transaction-confirmed"
    }

    public let analyticsContext: PurchaseAnalyticsContext
    public let productKind: MonetizationProductKind
    public let startedAt: Date
    public let reviewRequired: Bool
    public let belongsToCurrentSubject: Bool
    public let phase: Phase

    public var attemptID: MonetizationAttemptID {
        analyticsContext.attemptID
    }

    public var productID: ProductID {
        analyticsContext.productID
    }

    public init(
        analyticsContext: PurchaseAnalyticsContext,
        productKind: MonetizationProductKind,
        startedAt: Date,
        reviewRequired: Bool,
        belongsToCurrentSubject: Bool,
        phase: Phase
    ) {
        precondition(
            startedAt.timeIntervalSinceReferenceDate.isFinite,
            "Pending Apple purchase start date must be finite"
        )

        self.analyticsContext = analyticsContext
        self.productKind = productKind
        self.startedAt = startedAt
        self.reviewRequired = reviewRequired
        self.belongsToCurrentSubject = belongsToCurrentSubject
        self.phase = phase
    }
}

public enum PendingApplePurchaseState: Equatable, Sendable {
    case none
    case pending(PendingApplePurchaseIntent)
    case unavailable
}

/// Durable intent is written before StoreKit/Adapty opens its purchase sheet.
/// It remains present for `.pending` and subscription success that has not yet
/// produced authoritative entitlement, including across a cold launch.
public protocol PendingApplePurchaseStoreProtocol:
    PendingOperationBlockerProtocol {
    func begin(
        context: PurchaseAnalyticsContext,
        productKind: MonetizationProductKind
    ) async -> Bool

    func state() async -> PendingApplePurchaseState
    func markTransactionConfirmed(attemptID: MonetizationAttemptID) async -> Bool
    func clear(attemptID: MonetizationAttemptID) async -> Bool
}

public extension PendingApplePurchaseStoreProtocol {
    func hasPendingMonetizationOperation() async -> Bool {
        switch await state() {
        case .pending, .unavailable:
            true
        case .none:
            false
        }
    }
}
