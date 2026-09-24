import BroadCore
import Foundation

public protocol PurchaseSelectedProductUseCaseProtocol: Sendable {
    func callAsFunction(
        _ selection: ProductSelection,
        using checkoutMethod: CheckoutMethod
    ) async -> PurchaseOutcome
}

@main
enum ApplePurchaseRecoveryProbe {
    static func main() async {
        await checkCompletedPurchaseRecoversWithoutHistory()
        await checkVerifiedUpdateRecoversConfirmedPurchase()
        await checkUnknownOutcomeRemainsBlocked()
        await checkTerminalFailureAllowsImmediateRetry()
        await checkCancellationAllowsImmediateRetry()
        await checkUnrecognizedPremiumProductCannotCharge()
        print(
            "Apple purchase recovery passed: provider completion survives refresh failure; confirmed recovery does not require transaction date; terminal failure and cancellation allow retry; unknown outcome remains blocked; unrecognized premium SKU cannot start a charge."
        )
    }

    private static func checkCompletedPurchaseRecoversWithoutHistory() async {
        let fixture = Fixture(providerOutcome: .completed(Fixture.confirmation))
        let purchase = await fixture.purchase.callAsFunction(fixture.selection, using: .apple)
        guard case .completedButUnverified = purchase else {
            fatalError("A completed purchase with no fresh entitlement must keep waiting")
        }
        guard case let .pending(intent) = await fixture.store.state() else {
            fatalError("Completed purchase must retain its durable intent")
        }
        expect(intent.phase == .transactionConfirmed, "provider completion must persist before entitlement refresh")
        await expect(fixture.gate.isFinancialOperationBlocked(), "unverified entitlement keeps the financial gate closed")

        let recovery = await fixture.coordinator.applicationDidBecomeActive()
        guard case .activated = recovery else {
            fatalError("A fresh active entitlement must resolve a provider-confirmed purchase")
        }
        await expect(fixture.history.calls == 0, "confirmed purchase must not depend on a second history match")
        await expect(fixture.store.state() == .none, "recovered purchase clears durable intent")
        await expect(!(fixture.gate.isFinancialOperationBlocked()), "recovery releases the gate")
    }

    private static func checkVerifiedUpdateRecoversConfirmedPurchase() async {
        let fixture = Fixture(providerOutcome: .completed(Fixture.confirmation))
        _ = await fixture.purchase.callAsFunction(fixture.selection, using: .apple)
        let olderTransaction = VerifiedApplePurchaseTransaction(
            productID: fixture.selection.product.productID,
            purchaseDate: Date().addingTimeInterval(-3600),
            reason: .purchase
        )
        let recovery = await fixture.coordinator.verifiedTransactionUpdated(olderTransaction)
        guard case .activated = recovery else {
            fatalError("A confirmed purchase must retry entitlement without a timestamp match")
        }
        await expect(fixture.store.state() == .none, "verified update clears a confirmed purchase")
    }

    private static func checkUnknownOutcomeRemainsBlocked() async {
        let failure = AppError(
            kind: .unavailable,
            userMessage: "Unavailable",
            diagnosticCode: "fixture.unknown",
            isRetryable: true
        )
        let fixture = Fixture(providerOutcome: .failed(failure, disposition: .outcomeUnknown))
        let purchase = await fixture.purchase.callAsFunction(fixture.selection, using: .apple)
        expect(purchase == .pending, "unknown provider outcome remains pending")
        guard case let .pending(intent) = await fixture.store.state() else {
            fatalError("Unknown provider outcome must retain its durable intent")
        }
        expect(intent.phase == .initiated, "unknown outcome must not claim transaction confirmation")
        let recovery = await fixture.coordinator.applicationDidBecomeActive()
        guard case .pending = recovery else {
            fatalError("Missing StoreKit evidence must not unlock an unknown outcome")
        }
        await expect(fixture.history.calls == 1, "unknown outcome still checks verified history")
        await expect(fixture.gate.isFinancialOperationBlocked(), "unknown outcome keeps the gate closed")
    }

    private static func checkTerminalFailureAllowsImmediateRetry() async {
        let fixture = Fixture(providerOutcome: .failed(
            Fixture.error,
            disposition: .definitivelyNotPurchased
        ))
        for attempt in 1 ... 2 {
            guard case .failed = await fixture.purchase.callAsFunction(fixture.selection, using: .apple) else {
                fatalError("A definitive StoreKit refusal must return a failure")
            }
            await expect(fixture.provider.calls == attempt, "the purchase button must be able to start another attempt")
            await expect(fixture.store.state() == .none, "a terminal failure must clear its durable intent")
            await expect(!(fixture.gate.isFinancialOperationBlocked()), "a terminal failure must release the gate")
        }
    }

    private static func checkCancellationAllowsImmediateRetry() async {
        let fixture = Fixture(providerOutcome: .cancelled)
        for attempt in 1 ... 2 {
            let outcome = await fixture.purchase.callAsFunction(fixture.selection, using: .apple)
            expect(outcome == .cancelled, "a cancelled payment must remain cancelled")
            await expect(fixture.provider.calls == attempt, "cancellation must allow another purchase attempt")
            await expect(fixture.store.state() == .none, "cancellation must clear its durable intent")
            await expect(!(fixture.gate.isFinancialOperationBlocked()), "cancellation must release the gate")
        }
    }

    private static func checkUnrecognizedPremiumProductCannotCharge() async {
        let catalog = ApplePremiumProductCatalog(entries: [
            .init(productID: "fixture.other-premium", kind: .autoRenewable)
        ])
        let fixture = Fixture(providerOutcome: .completed(Fixture.confirmation), catalog: catalog)
        guard case .failed = await fixture.purchase.callAsFunction(fixture.selection, using: .apple) else {
            fatalError("A premium SKU missing from entitlement catalog must be rejected")
        }
        await expect(fixture.provider.calls == 0, "catalog mismatch must not open the provider purchase")
        await expect(fixture.store.state() == .none, "catalog mismatch must not create a pending intent")
        await expect(!(fixture.gate.isFinancialOperationBlocked()), "catalog mismatch must not block later purchases")
    }

    private static func expect(_ condition: Bool, _ message: String) {
        guard condition else { fatalError("Apple purchase contract violation: \(message)") }
    }
}

private struct Fixture {
    static let confirmation = PurchaseConfirmation(
        productID: ProductID(rawValue: "fixture.premium"),
        checkoutMethod: .apple,
        confirmedAt: Date()
    )

    let store = InMemoryPendingApplePurchaseStore()
    let gate = MonetizationOperationGate()
    let history = FixtureHistory()
    let entitlement = FixtureEntitlement()
    let provider: FixturePurchase
    let selection: ProductSelection
    let purchase: PurchaseSelectedProductUseCase
    let coordinator: PendingApplePurchaseCoordinator

    init(
        providerOutcome: PurchaseAttemptOutcome,
        catalog: ApplePremiumProductCatalog = ApplePremiumProductCatalog(entries: [
            .init(productID: "fixture.premium", kind: .autoRenewable)
        ])
    ) {
        let product = MonetizationProduct(
            presentationID: .generated(),
            reference: ProductReference(rawValue: "fixture-product"),
            productID: ProductID(rawValue: "fixture.premium"),
            kind: .autoRenewableSubscription,
            price: Money(amount: 1, currencyCode: "USD"),
            catalogSource: .adapty
        )
        let paywall = PaywallPayload(
            presentationID: .generated(),
            paywallReference: PaywallReference(rawValue: "fixture-paywall"),
            origin: PaywallOrigin(
                requestedPlacementID: .main,
                resolvedPlacementID: .main,
                catalogSource: .adapty
            ),
            products: [product],
            fetchedAt: Date()
        )
        selection = ProductSelection(paywall: paywall, product: product)
        provider = FixturePurchase(providerOutcome)
        purchase = PurchaseSelectedProductUseCase(
            repository: provider,
            entitlementRepository: entitlement,
            analytics: FixtureAnalytics(),
            pendingStore: store,
            operationGate: gate,
            inProgressError: Fixture.error,
            premiumProductCatalog: catalog
        )
        coordinator = PendingApplePurchaseCoordinator(
            store: store,
            refreshEntitlement: entitlement,
            transactionRecovery: history,
            analytics: FixtureAnalytics(),
            operationGate: gate
        )
    }

    static let error = AppError(
        kind: .unavailable,
        userMessage: "Unavailable",
        diagnosticCode: "fixture.unavailable",
        isRetryable: true
    )
}

private actor FixturePurchase: PurchaseRepositoryProtocol {
    let outcome: PurchaseAttemptOutcome
    private(set) var calls = 0

    init(_ outcome: PurchaseAttemptOutcome) {
        self.outcome = outcome
    }

    func purchase(_: PurchaseRequest) async -> PurchaseAttemptOutcome {
        calls += 1
        return outcome
    }
}

private actor FixtureEntitlement: EntitlementRepositoryProtocol {
    private var refreshCount = 0

    func refreshEntitlement(policy _: EntitlementRefreshPolicy) async -> EntitlementSnapshot {
        refreshCount += 1
        let active = refreshCount > 1
        return EntitlementSnapshot(
            state: active ? .active : .unresolved,
            sources: [EntitlementSourceEvaluation(
                source: .apple,
                state: active ? .active : .unresolved,
                freshness: active ? .refreshed : .unresolved,
                activeValidity: active ? .lifetime : nil,
                validatedAt: active ? Date() : nil
            )],
            activeValidity: active ? .lifetime : nil,
            freshness: active ? .refreshed : .unresolved,
            validatedAt: active ? Date() : nil,
            evaluatedAt: Date()
        )
    }

    func latestEntitlement() async -> EntitlementSnapshot? {
        nil
    }
}

private actor FixtureHistory: PendingAppleTransactionRecoveryProtocol {
    private(set) var calls = 0

    func recover(_: PendingApplePurchaseIntent) async -> PendingAppleTransactionRecoveryOutcome {
        calls += 1
        return .noMatch
    }
}

private actor FixtureAnalytics: MonetizationAnalyticsProtocol {
    func track(_: MonetizationAnalyticsEvent) async {}
}
