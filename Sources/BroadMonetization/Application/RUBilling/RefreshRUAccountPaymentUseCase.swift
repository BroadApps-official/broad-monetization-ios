import BroadCore

struct RefreshRUAccountPaymentUseCase: RefreshRUPaymentUseCaseProtocol {
    let repository: any RUAccountPolicyRepositoryProtocol
    let refreshEntitlement: any RefreshEntitlementUseCaseProtocol
    let authorizationBinding: SubjectAuthorizationBinding
    let policy: RUPaymentPollingPolicy

    func callAsFunction(checkoutSessionID _: CheckoutSessionID) async -> RUPaymentRefreshOutcome {
        .unavailable(RUBillingSafeErrors.paymentStatusUnavailable)
    }

    func callAsFunction(
        checkoutSessionID _: CheckoutSessionID,
        productID: RUCatalogProductID,
        accountExpectation: RUAccountCheckoutExpectation?
    ) async -> RUPaymentRefreshOutcome {
        guard let expectation = accountExpectation else {
            return .unavailable(RUBillingSafeErrors.paymentStatusUnavailable)
        }
        var sawFreshPolicy = false
        for attempt in 1 ... policy.maximumAttempts {
            guard !Task.isCancelled, authorizationBinding.isCurrent() else {
                return .unavailable(RUBillingSafeErrors.paymentStatusUnavailable)
            }
            let outcome = await repository.loadPolicy(for: authorizationBinding.subject)
            guard !Task.isCancelled, authorizationBinding.isCurrent() else {
                return .unavailable(RUBillingSafeErrors.paymentStatusUnavailable)
            }
            if case let .loaded(account) = outcome,
               account.subject == authorizationBinding.subject {
                sawFreshPolicy = true
                if let result = await confirmedOutcome(account, expectation: expectation, productID: productID) {
                    return result
                }
            }
            if attempt < policy.maximumAttempts && policy.delay > .zero {
                do {
                    try await ContinuousClock().sleep(for: policy.delay)
                } catch {
                    return .unavailable(RUBillingSafeErrors.paymentStatusUnavailable)
                }
            }
        }
        // Inactive account state cannot prove that a checkout was cancelled.
        return sawFreshPolicy ? .pending : .unavailable(RUBillingSafeErrors.paymentStatusUnavailable)
    }

    private func confirmedOutcome(
        _ account: RUAccountPolicy,
        expectation: RUAccountCheckoutExpectation,
        productID: RUCatalogProductID
    ) async -> RUPaymentRefreshOutcome? {
        guard expectation.isConfirmed(by: account, productID: productID) else { return nil }
        if expectation.kind == .tokens, let balance = account.creditsBalance {
            return .tokensCredited(balance)
        }
        let snapshot = await refreshEntitlement(policy: .startNewGeneration)
        guard !Task.isCancelled, authorizationBinding.isCurrent() else {
            return .unavailable(RUBillingSafeErrors.paymentStatusUnavailable)
        }
        return snapshot.confirmsRUPaymentAccess ? .active(snapshot) : nil
    }
}
