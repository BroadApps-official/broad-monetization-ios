import BroadCore

/// Result of asking the application's backend to reconcile every known token
/// purchase for the current account and return its authoritative balance.
public enum TokenAccountRecoveryOutcome: Equatable, Sendable {
    case restored(TokenBalanceSnapshot)
    case unavailable(AppError)
}

public protocol RecoverTokenAccountUseCaseProtocol: Sendable {
    /// The backend must reconcile both Apple and RU token ledgers before it
    /// returns the balance. The device never reconstructs a balance locally.
    func callAsFunction() async -> TokenAccountRecoveryOutcome
}

public enum CustomerAccessRecoveryComponent<Value: Equatable & Sendable>: Equatable, Sendable {
    case restored(Value)
    case notConfigured
    case authenticationRequired
    case unavailable(AppError)
}

/// One fresh-install snapshot. Local cache may improve offline UX, but none of
/// these values is restored from an installation-scoped flag.
public struct CustomerAccessRecoverySnapshot: Equatable, Sendable {
    public let activation: MonetizationActivationOutcome
    public let entitlement: EntitlementSnapshot
    public let tokens: CustomerAccessRecoveryComponent<TokenBalanceSnapshot>
    public let ruSubscription:
        CustomerAccessRecoveryComponent<RUSubscriptionManagementStatus>

    public init(
        activation: MonetizationActivationOutcome,
        entitlement: EntitlementSnapshot,
        tokens: CustomerAccessRecoveryComponent<TokenBalanceSnapshot>,
        ruSubscription:
        CustomerAccessRecoveryComponent<RUSubscriptionManagementStatus>
    ) {
        self.activation = activation
        self.entitlement = entitlement
        self.tokens = tokens
        self.ruSubscription = ruSubscription
    }
}

public protocol RecoverCustomerAccessUseCaseProtocol: Sendable {
    func callAsFunction() async -> CustomerAccessRecoverySnapshot
}
