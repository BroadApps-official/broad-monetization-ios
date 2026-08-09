public struct CancelRUSubscriptionUseCase: CancelRUSubscriptionUseCaseProtocol {
    private let repository: any RUSubscriptionRepositoryProtocol
    private let refreshEntitlement: any RefreshEntitlementUseCaseProtocol
    private let authorizationBinding: SubjectAuthorizationBinding

    public init(
        repository: any RUSubscriptionRepositoryProtocol,
        refreshEntitlement: any RefreshEntitlementUseCaseProtocol,
        authorizationBinding: SubjectAuthorizationBinding
    ) {
        self.repository = repository
        self.refreshEntitlement = refreshEntitlement
        self.authorizationBinding = authorizationBinding
    }

    public func callAsFunction(
        subscriptionID: RUSubscriptionID
    ) async -> RUSubscriptionCancellationOutcome {
        guard authorizationBinding.isCurrent() else {
            return .unavailable(RUBillingSafeErrors.cancellationUnavailable)
        }
        let outcome = await repository.cancelSubscription(id: subscriptionID)
        guard authorizationBinding.isCurrent() else {
            return .unavailable(RUBillingSafeErrors.cancellationUnavailable)
        }
        switch outcome {
        case .cancelled, .alreadyInactive:
            _ = await refreshEntitlement(policy: .startNewGeneration)
            guard authorizationBinding.isCurrent() else {
                return .unavailable(RUBillingSafeErrors.cancellationUnavailable)
            }
        case .unavailable, .failed:
            break
        }
        return outcome
    }
}
