import BroadCore
import Foundation

/// A fresh account response, not a receipt or a payment-session status.
public struct RUAccountPolicy: Equatable, Sendable {
    public let subject: EntitlementSubject
    public let isSubscribed: Bool
    public let plan: String?
    public let creditsBalance: Int?

    public init(subject: EntitlementSubject, isSubscribed: Bool, plan: String?, creditsBalance: Int?) {
        self.subject = subject
        self.isSubscribed = isSubscribed
        self.plan = plan
        self.creditsBalance = creditsBalance
    }
}

public enum RUAccountPolicyOutcome: Equatable, Sendable {
    case loaded(RUAccountPolicy)
    case unavailable(AppError)
}

/// Each call must perform a fresh authenticated backend read. Never return
/// cached account state after a failed request. A host can reuse its API client.
public protocol RUAccountPolicyRepositoryProtocol: Sendable {
    func loadPolicy(for subject: EntitlementSubject) async -> RUAccountPolicyOutcome
}

/// Persisted alongside the subject-scoped checkout. A balance baseline is
/// captured before token checkout creation and is never replaced during retry.
public struct RUAccountCheckoutExpectation: Codable, Equatable, Sendable {
    public let kind: RUCatalogProductKind
    public let subscriptionPeriod: SubscriptionPeriod
    public let creditsBalanceBeforeCheckout: Int?

    public init(
        kind: RUCatalogProductKind,
        subscriptionPeriod: SubscriptionPeriod = .unknown,
        creditsBalanceBeforeCheckout: Int? = nil
    ) {
        self.kind = kind
        self.subscriptionPeriod = subscriptionPeriod
        self.creditsBalanceBeforeCheckout = creditsBalanceBeforeCheckout
    }

    func isConfirmed(by policy: RUAccountPolicy, productID: RUCatalogProductID) -> Bool {
        switch kind {
        case .tokens:
            guard let before = creditsBalanceBeforeCheckout, before >= 0,
                  let after = policy.creditsBalance else { return false }
            return after > before
        case .subscription:
            guard policy.isSubscribed,
                  let plan = policy.plan?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                  !plan.isEmpty else { return false }
            let product = productID.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if plan == product {
                return true
            }
            let expected = subscriptionPeriod == .unknown
                ? Self.inferredPeriod(product) : subscriptionPeriod
            guard let actual = Self.inferredPeriod(plan), let expected else { return false }
            return actual == expected
        case .coupon, .unknown:
            return false
        }
    }

    /// Compatibility with policy.plan values used by the apps. This is only
    /// confirmation matching; catalog selection still requires exact IDs.
    private static func inferredPeriod(_ value: String) -> SubscriptionPeriod? {
        if value.contains("year") || value.contains("annual") {
            return .year()
        }
        if value.contains("month") {
            return .month()
        }
        if value.contains("week") {
            return .week()
        }
        if value.contains("day") || value == "daily" {
            return .day()
        }
        return nil
    }
}
