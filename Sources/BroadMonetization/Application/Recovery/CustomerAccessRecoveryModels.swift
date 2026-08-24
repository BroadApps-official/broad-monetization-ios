import BroadCore

/// Result of asking the application's backend for the current authenticated
/// account's authoritative token balance.
public enum TokenAccountRecoveryOutcome: Equatable, Sendable {
    case restored(TokenBalanceSnapshot)
    case unavailable(AppError)
}

public protocol RecoverTokenAccountUseCaseProtocol: Sendable {
    /// Fetches one full balance snapshot for the authenticated app account.
    /// StoreKit transaction and RU checkout identifiers belong to fulfillment
    /// duplicate protection; the device does not submit an ID list or rebuild
    /// the balance during ordinary recovery.
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
