public extension BroadMonetizationServices {
    /// Builds the fresh-install recovery boundary from the same activation
    /// service as purchase/paywall flows. Backend adapters remain app-owned.
    func makeCustomerAccessRecovery(
        subject: EntitlementSubject,
        refreshEntitlement: any RefreshEntitlementUseCaseProtocol,
        recoverTokenAccount:
        (any RecoverTokenAccountUseCaseProtocol)? = nil,
        loadRUSubscription:
        (any LoadRUSubscriptionStatusUseCaseProtocol)? = nil
    ) -> RecoverCustomerAccessUseCase {
        RecoverCustomerAccessUseCase(
            subject: subject,
            activate: activate,
            refreshEntitlement: refreshEntitlement,
            recoverTokenAccount: recoverTokenAccount,
            loadRUSubscription: loadRUSubscription
        )
    }
}
