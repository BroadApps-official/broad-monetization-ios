/// Restores server-authoritative customer state after install, reinstall,
/// login or account switch. Call only after the host has resolved its account.
public struct RecoverCustomerAccessUseCase:
    RecoverCustomerAccessUseCaseProtocol {
    private let subject: EntitlementSubject
    private let activate: any ActivateMonetizationUseCaseProtocol
    private let refreshEntitlement: any RefreshEntitlementUseCaseProtocol
    private let recoverTokenAccount:
        (any RecoverTokenAccountUseCaseProtocol)?
    private let loadRUSubscription:
        (any LoadRUSubscriptionStatusUseCaseProtocol)?

    public init(
        subject: EntitlementSubject,
        activate: any ActivateMonetizationUseCaseProtocol,
        refreshEntitlement: any RefreshEntitlementUseCaseProtocol,
        recoverTokenAccount:
        (any RecoverTokenAccountUseCaseProtocol)? = nil,
        loadRUSubscription:
        (any LoadRUSubscriptionStatusUseCaseProtocol)? = nil
    ) {
        self.subject = subject
        self.activate = activate
        self.refreshEntitlement = refreshEntitlement
        self.recoverTokenAccount = recoverTokenAccount
        self.loadRUSubscription = loadRUSubscription
    }

    public func callAsFunction() async -> CustomerAccessRecoverySnapshot {
        let activation = await activate()
        async let entitlement = refreshEntitlement(
            policy: .startNewGeneration
        )
        async let tokens = recoverTokens()
        async let ruSubscription = recoverRUSubscription()

        return await CustomerAccessRecoverySnapshot(
            activation: activation,
            entitlement: entitlement,
            tokens: tokens,
            ruSubscription: ruSubscription
        )
    }
}

private extension RecoverCustomerAccessUseCase {
    var hasStableAccount: Bool {
        subject != .anonymous
    }

    func recoverTokens()
        async -> CustomerAccessRecoveryComponent<TokenBalanceSnapshot> {
        guard let recoverTokenAccount else {
            return .notConfigured
        }
        guard hasStableAccount else {
            return .authenticationRequired
        }

        switch await recoverTokenAccount() {
        case let .restored(balance):
            return .restored(balance)
        case let .unavailable(error):
            return .unavailable(error)
        }
    }

    func recoverRUSubscription()
        async -> CustomerAccessRecoveryComponent<RUSubscriptionManagementStatus> {
        guard let loadRUSubscription else {
            return .notConfigured
        }
        guard hasStableAccount else {
            return .authenticationRequired
        }

        switch await loadRUSubscription() {
        case let .loaded(status):
            return .restored(status)
        case let .unavailable(error):
            return .unavailable(error)
        }
    }
}
