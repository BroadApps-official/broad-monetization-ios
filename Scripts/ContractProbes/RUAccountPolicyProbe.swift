import BroadCore
import Foundation

@main
enum RUAccountPolicyProbe {
    static let failure = RUBillingSafeErrors.paymentStatusUnavailable
    static let productID = RUCatalogProductID(rawValue: "fixture-monthly")
    static let subscription = RUAccountCheckoutExpectation(kind: .subscription, subscriptionPeriod: .month())
    static let tokens = RUAccountCheckoutExpectation(kind: .tokens, creditsBalanceBeforeCheckout: 100)

    static func main() async throws {
        try wireContracts()
        try persistenceContracts()
        await pollingContracts()
        await returnContracts()
        print("RU account-policy contracts passed: wire, persistence, plan, balance, retry, subject, epoch and return coalescing.")
    }

    static func wireContracts() throws {
        let wire = BroadAppsAccountPolicyWireContract()
        for json in [
            #"{"isSubscribed":true,"plan":"monthly","creditsBalance":101}"#,
            #"{"is_subscribed":true,"plan":"monthly","credits_balance":101}"#
        ] {
            let policy = try wire.decodePolicy(from: Data(json.utf8), subject: .anonymous)
            check(subscription.isConfirmed(by: policy, productID: productID))
            check(tokens.isConfirmed(by: policy, productID: productID))
        }
        for json in [#"{}"#, #"{"isSubscribed":"true"}"#, #"{"isSubscribed":false,"creditsBalance":-1}"#] {
            check((try? wire.decodePolicy(from: Data(json.utf8), subject: .anonymous)) == nil)
        }
        let checkout = Data(#"{"status":"success","paymentUrl":"https://example.com/checkout"}"#.utf8)
        let first = try wire.decodeCheckoutSession(from: checkout)
        let second = try wire.decodeCheckoutSession(from: checkout)
        check(first.id != second.id)
        check((try? wire.decodeCheckoutSession(from: Data(#"{"paymentUrl":"http://example.com/checkout"}"#.utf8))) == nil)
        let legacy = BroadAppsRUBillingWireContract()
        let legacyData = Data(#"{"checkout_session_id":"fixture-session","payment_url":"https://example.com/checkout"}"#.utf8)
        let session = try legacy.decodeCheckoutSession(from: legacyData)
        check(session.id.rawValue == "fixture-session")
        let paid = try legacy.decodePaymentStatus(
            from: Data(#"{"checkout_session_id":"fixture-session","status":"paid"}"#.utf8),
            expectedCheckoutSessionID: session.id, checkedAt: Date()
        )
        check(paid.status == .paid)
    }

    static func persistenceContracts() throws {
        let pending = context(expectation: tokens)
        let data = try JSONEncoder().encode(pending)
        let restored = try JSONDecoder().decode(PendingRUCheckoutContext.self, from: data)
        check(restored == pending && restored.accountExpectation?.creditsBalanceBeforeCheckout == 100)
        let old = context(expectation: nil)
        let restoredOld = try JSONDecoder().decode(PendingRUCheckoutContext.self, from: JSONEncoder().encode(old))
        check(restoredOld.accountExpectation == nil)
    }

    static func pollingContracts() async {
        let session = SubjectAuthorizationSession()
        let binding = session.begin(for: .anonymous)
        let active = account(plan: "fixture-monthly", balance: 100)
        let wrong = account(plan: "yearly", balance: 100)
        check(!subscription.isConfirmed(
            by: .init(subject: .anonymous, isSubscribed: false, plan: "monthly", creditsBalance: 100),
            productID: productID
        ))
        check(!subscription.isConfirmed(by: account(plan: nil, balance: 100), productID: productID))
        check(!RUAccountCheckoutExpectation(kind: .tokens).isConfirmed(by: active, productID: productID))

        let wrongRepo = PolicyRepository([.loaded(wrong)])
        await check(run(wrongRepo, binding: binding, expectation: subscription) == .pending)
        await check(wrongRepo.calls == 8)
        let lag = PolicyRepository([.unavailable(failure), .loaded(wrong), .loaded(active)])
        if case .active = await run(lag, binding: binding, expectation: subscription) {} else {
            fatalError("Expected active")
        }
        await check(lag.calls == 3)
        await check(run(PolicyRepository([.loaded(active)]), binding: binding, expectation: tokens) == .pending)
        await check(run(
            PolicyRepository([.loaded(account(plan: nil, balance: 101))]),
            binding: binding,
            expectation: tokens
        ) == .tokensCredited(101))
        let offline = PolicyRepository([.unavailable(failure)])
        await check(run(offline, binding: binding, expectation: subscription) == .unavailable(failure))
        await check(offline.calls == 8)
        await check(run(
            PolicyRepository([.loaded(active)]),
            binding: binding,
            expectation: subscription,
            fresh: false
        ) == .pending)
        let logout = PolicyRepository([.loaded(active)], onRead: { session.invalidate() })
        await check(run(logout, binding: binding, expectation: subscription) == .unavailable(failure))
        await check(logout.calls == 1)
    }

    static func returnContracts() async {
        let session = SubjectAuthorizationSession()
        let binding = session.begin(for: .anonymous)
        let repository = PolicyRepository([.loaded(account(plan: nil, balance: 101))], slow: true)
        let store = PendingStore(context(expectation: tokens))
        let gate = MonetizationOperationGate()
        gate.registerPendingOperationBlocker(store)
        let coordinator = RUPaymentReturnCoordinator(
            pendingStore: store, refreshPayment: refresh(repository, binding: binding), operationGate: gate
        )
        async let foreground = coordinator.applicationDidBecomeActive()
        async let dismiss = coordinator.applicationDidBecomeActive()
        let outcomes = await [foreground, dismiss]
        check(outcomes == [.tokensCredited(101), .tokensCredited(101)])
        await check(repository.calls == 1)
        await check(!gate.isFinancialOperationBlocked())
        await check(coordinator.applicationDidBecomeActive() == .noPendingCheckout)
        let pending = PendingStore(context(expectation: tokens))
        let waiting = RUPaymentReturnCoordinator(
            pendingStore: pending,
            refreshPayment: refresh(PolicyRepository([.loaded(account(plan: nil, balance: 100))]), binding: binding),
            operationGate: gate
        )
        await check(waiting.applicationDidBecomeActive() == .pending)
        await check(pending.hasPendingMonetizationOperation())
    }

    private static func run(
        _ repository: PolicyRepository,
        binding: SubjectAuthorizationBinding,
        expectation: RUAccountCheckoutExpectation,
        fresh: Bool = true
    ) async -> RUPaymentRefreshOutcome {
        await refresh(repository, binding: binding, fresh: fresh)(
            checkoutSessionID: .init(rawValue: "fixture-session"), productID: productID, accountExpectation: expectation
        )
    }

    private static func refresh(
        _ repository: PolicyRepository,
        binding: SubjectAuthorizationBinding,
        fresh: Bool = true
    ) -> RefreshRUAccountPaymentUseCase {
        .init(
            repository: repository,
            refreshEntitlement: Entitlement(fresh: fresh),
            authorizationBinding: binding,
            policy: .init(maximumAttempts: 8, delay: .zero)
        )
    }

    static func account(plan: String?, balance: Int) -> RUAccountPolicy {
        .init(subject: .anonymous, isSubscribed: true, plan: plan, creditsBalance: balance)
    }

    static func context(expectation: RUAccountCheckoutExpectation?) -> PendingRUCheckoutContext {
        .init(
            checkoutSessionID: .init(rawValue: "fixture-session"),
            attemptID: .generated(),
            productID: productID,
            checkoutMethod: .card,
            startedAt: Date(),
            expiresAt: nil,
            accountExpectation: expectation
        )
    }

    static func check(_ value: Bool, line: UInt = #line) {
        precondition(value, "Account policy contract failed at \(line)")
    }
}

private actor PolicyRepository: RUAccountPolicyRepositoryProtocol {
    var calls = 0
    let outcomes: [RUAccountPolicyOutcome]
    let onRead: @Sendable () -> Void
    let slow: Bool

    init(_ outcomes: [RUAccountPolicyOutcome], onRead: @escaping @Sendable () -> Void = {}, slow: Bool = false) {
        self.outcomes = outcomes
        self.onRead = onRead
        self.slow = slow
    }

    func loadPolicy(for _: EntitlementSubject) async -> RUAccountPolicyOutcome {
        calls += 1
        if slow {
            try? await Task.sleep(for: .milliseconds(40))
        }
        onRead()
        return outcomes[min(calls - 1, outcomes.count - 1)]
    }
}

private struct Entitlement: RefreshEntitlementUseCaseProtocol {
    let fresh: Bool
    func callAsFunction(policy _: EntitlementRefreshPolicy) async -> EntitlementSnapshot {
        let freshness: EntitlementFreshness = fresh ? .refreshed : .cached
        return .init(state: .active, sources: [
            .init(source: .ruBilling, state: .active, freshness: freshness, activeValidity: .unspecified, validatedAt: Date())
        ], activeValidity: .unspecified, freshness: freshness, validatedAt: Date(), evaluatedAt: Date())
    }
}

private actor PendingStore: PendingRUCheckoutStoreProtocol {
    nonisolated let pendingOperationBlockerKey = PendingOperationBlockerKey(kind: .ruCheckout, applicationIdentifier: "fixture")
    var context: PendingRUCheckoutContext?
    init(_ context: PendingRUCheckoutContext) {
        self.context = context
    }

    func state() -> PendingRUCheckoutState {
        context.map(PendingRUCheckoutState.pending) ?? .none
    }

    func hasPendingMonetizationOperation() -> Bool {
        context != nil
    }

    func save(_ context: PendingRUCheckoutContext) -> Bool {
        self.context = context; return true
    }

    func clear(checkoutSessionID: CheckoutSessionID, attemptID: MonetizationAttemptID) -> Bool {
        guard context?.checkoutSessionID == checkoutSessionID, context?.attemptID == attemptID else { return false }
        context = nil
        return true
    }
}
