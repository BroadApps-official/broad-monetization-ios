import BroadCore
import Foundation

enum RUWaitingStoreProbe {
    static func run() async {
        await preflightContract()
        let session = SubjectAuthorizationSession()
        let binding = session.begin(for: .anonymous)
        let storage = WaitingMemoryStorage()
        let cache = VersionedJSONCacheRepository(keyValueStore: storage)
        let store = makeStore(cache, binding: binding)
        let first = RUAccountPolicyProbe.context(expectation: RUAccountPolicyProbe.tokens)
        await check(store.save(first))
        await check(store.hasPendingMonetizationOperation())
        await check(!store.save(RUAccountPolicyProbe.context(expectation: RUAccountPolicyProbe.tokens)))
        await check(!store.finishWaiting(checkoutSessionID: first.checkoutSessionID, attemptID: .generated()))
        await storage.failWrites(true)
        await check(!store.finishWaiting(checkoutSessionID: first.checkoutSessionID, attemptID: first.attemptID))
        await check(store.hasPendingMonetizationOperation())
        await storage.failWrites(false)
        await check(store.finishWaiting(checkoutSessionID: first.checkoutSessionID, attemptID: first.attemptID))
        await check(store.state() == .awaitingReconciliation(first))
        let relaunched = makeStore(cache, binding: binding)
        await check(!relaunched.hasPendingMonetizationOperation())
        let gate = MonetizationOperationGate()
        gate.registerPendingOperationBlocker(relaunched)
        for kind: MonetizationOperationKind in [.purchase, .tokenPurchase, .restore, .ruCheckout] {
            guard let lease = await gate.acquire(kind) else { fatalError("Completed wait blocked a new operation") }
            await check(gate.acquire(kind) == nil)
            await gate.release(lease)
        }
        let second = RUAccountPolicyProbe.context(expectation: RUAccountPolicyProbe.tokens)
        await check(relaunched.save(second))
        await check(!store.clear(checkoutSessionID: first.checkoutSessionID, attemptID: first.attemptID))
        await check(!store.finishWaiting(checkoutSessionID: first.checkoutSessionID, attemptID: first.attemptID))
        await check(relaunched.state() == .pending(second))
        session.invalidate()
        await check(!relaunched.finishWaiting(checkoutSessionID: second.checkoutSessionID, attemptID: second.attemptID))
        let freshBinding = session.begin(for: .anonymous)
        let recovered = makeStore(cache, binding: freshBinding)
        await check(recovered.hasPendingMonetizationOperation())
        await check(recovered.clear(checkoutSessionID: second.checkoutSessionID, attemptID: second.attemptID))
        let legacy = RUAccountPolicyProbe.context(expectation: nil)
        await check(recovered.save(legacy))
        await check(!recovered.finishWaiting(checkoutSessionID: legacy.checkoutSessionID, attemptID: legacy.attemptID))
        await check(recovered.hasPendingMonetizationOperation())
        await accountSwitchContract(cache, session: session, store: recovered, context: legacy)
    }

    private static func makeStore(
        _ cache: VersionedJSONCacheRepository, binding: SubjectAuthorizationBinding
    ) -> PendingRUCheckoutStore {
        .init(subject: binding.subject, applicationIdentifier: "fixture", authorizationBinding: binding, cache: cache)
    }

    private static func accountSwitchContract(
        _ cache: VersionedJSONCacheRepository, session: SubjectAuthorizationSession,
        store: PendingRUCheckoutStore, context: PendingRUCheckoutContext
    ) async {
        await check(store.clear(checkoutSessionID: context.checkoutSessionID, attemptID: context.attemptID))
        let pending = RUAccountPolicyProbe.context(expectation: RUAccountPolicyProbe.tokens)
        await check(store.save(pending))
        await check(store.finishWaiting(checkoutSessionID: pending.checkoutSessionID, attemptID: pending.attemptID))
        let otherSubject = EntitlementSubject.fingerprinted(.init(bytes: Data(repeating: 1, count: 32)))
        let other = makeStore(cache, binding: session.begin(for: otherSubject))
        await check(other.state() == .none)
        await check(!other.hasPendingMonetizationOperation())
        await check(!other.finishWaiting(checkoutSessionID: pending.checkoutSessionID, attemptID: pending.attemptID))
        let next = RUAccountPolicyProbe.context(expectation: RUAccountPolicyProbe.tokens)
        await check(other.save(next))
        let original = makeStore(cache, binding: session.begin(for: .anonymous))
        await check(original.state() == .blockedByAnotherSubject)
        await check(original.hasPendingMonetizationOperation())
    }

    private static func check(_ value: Bool, line: UInt = #line) {
        precondition(value, "RU waiting storage contract failed at \(line)")
    }

    private static func preflightContract() async {
        let session = SubjectAuthorizationSession()
        let binding = session.begin(for: .anonymous)
        let store = makeStore(VersionedJSONCacheRepository(keyValueStore: WaitingMemoryStorage()), binding: binding)
        let policy = CheckoutPolicy()
        let checkout = CheckoutFixture(binding: binding)
        let flow = RUCheckoutFlowCoordinator(
            checkout: checkout, authorizationProvider: checkout,
            gate: RUBillingGate(isFeatureEnabled: true), storefrontRepository: checkout,
            opener: checkout, pendingStore: store, operationGate: MonetizationOperationGate(),
            accountPolicyRepository: policy, authorizationBinding: binding
        )
        let product = MonetizationProduct(
            presentationID: .generated(), reference: .init(rawValue: "fixture-product"),
            productID: .init(rawValue: "fixture.monthly"), kind: .autoRenewableSubscription,
            price: Money(amount: 1, currencyCode: "RUB"), catalogSource: .ruBackend
        )
        let paywall = PaywallPayload(
            presentationID: .generated(), paywallReference: .init(rawValue: "fixture-paywall"),
            origin: .init(requestedPlacementID: .main, resolvedPlacementID: .main, catalogSource: .ruBackend),
            products: [product], fetchedAt: Date()
        )
        let selection = ProductSelection(paywall: paywall, product: product)
        let request = RUCheckoutRequest(productID: RUAccountPolicyProbe.productID, method: .card, acceptsAutoRenewal: true)
        let remote = RemotePaywallConfiguration(isRUBillingEnabled: true).qualified(by: .verifiedFreshRemote)
        // An active subscription or an offline account must not create another link.
        for outcome: RUAccountPolicyOutcome in [
            .loaded(.init(subject: .anonymous, isSubscribed: true, plan: "monthly", creditsBalance: 100)),
            .unavailable(RUBillingSafeErrors.paymentStatusUnavailable)
        ] {
            await policy.update(outcome)
            _ = await flow.start(
                request,
                selection: selection,
                remoteConfiguration: remote,
                accountExpectation: RUAccountPolicyProbe.subscription
            )
            await check(checkout.calls == 0)
        }
        // Repeated token attempts capture a fresh baseline rather than reusing
        // the balance of an abandoned attempt. The opener never touches a UI.
        for balance in [100, 150] {
            await policy.update(.loaded(.init(subject: .anonymous, isSubscribed: false, plan: nil, creditsBalance: balance)))
            let result = await flow.start(
                request,
                selection: selection,
                remoteConfiguration: remote,
                accountExpectation: RUAccountPolicyProbe.tokens
            )
            guard case let .opened(context) = result else { fatalError("Expected fixture checkout") }
            check(context.accountExpectation?.creditsBalanceBeforeCheckout == balance)
            await check(store.finishWaiting(checkoutSessionID: context.checkoutSessionID, attemptID: context.attemptID))
        }
        await check(checkout.calls == 2)
    }
}

private actor CheckoutPolicy: RUAccountPolicyRepositoryProtocol {
    var outcome: RUAccountPolicyOutcome = .unavailable(RUBillingSafeErrors.paymentStatusUnavailable)
    func update(_ outcome: RUAccountPolicyOutcome) {
        self.outcome = outcome
    }

    func loadPolicy(for _: EntitlementSubject) -> RUAccountPolicyOutcome {
        outcome
    }
}

private actor CheckoutFixture: CreateRUCheckoutUseCaseProtocol, SubjectAuthorizationProviderProtocol,
    StorefrontRepositoryProtocol, PaymentURLOpenerProtocol {
    let binding: SubjectAuthorizationBinding
    var calls = 0

    init(binding: SubjectAuthorizationBinding) {
        self.binding = binding
    }

    func authorization(for subject: EntitlementSubject) -> SubjectBoundAuthorization? {
        .init(subject: subject, bearerToken: "fixture-token")
    }

    func currentStorefront() -> StorefrontResolution {
        .available(.init(countryCode: "RU"))
    }

    @MainActor
    func open(_: URL) async -> Bool {
        true
    }

    func callAsFunction(_: RUCheckoutRequest) -> RUCheckoutCreationOutcome {
        calls += 1
        return .created(
            .init(id: .init(rawValue: "fixture-session-\(calls)"), paymentURL: URL(string: "https://example.com/checkout")!),
            authorizationProof: .init(authorization: authorization(for: .anonymous)!, binding: binding)
        )
    }
}

private actor WaitingMemoryStorage: KeyValueStoreProtocol {
    private var entries: [String: Data] = [:]
    private var writesFail = false

    func failWrites(_ value: Bool) {
        writesFail = value
    }

    func read(_ key: String) -> KeyValueStoreEntry {
        entries[key].map(KeyValueStoreEntry.data) ?? .missing
    }

    func write(_ data: Data, forKey key: String) throws {
        if writesFail {
            throw CacheRepositoryError.encodingFailed
        }
        entries[key] = data
    }

    func write(_ data: Data, forKey key: String, ifMatching snapshot: KeyValueStoreEntry) throws -> Bool {
        guard read(key) == snapshot else { return false }
        try write(data, forKey: key)
        return true
    }

    func remove(_ key: String) {
        entries[key] = nil
    }

    func remove(_ key: String, ifMatching snapshot: KeyValueStoreEntry) -> Bool {
        guard read(key) == snapshot else { return false }
        remove(key)
        return true
    }
}
