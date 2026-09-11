import BroadCore
import Foundation

@main
enum TokenPurchaseProbe {
    private static let balance = TokenBalanceSnapshot(balance: 2000, updatedAt: Date())

    static func main() async {
        for first in [
            TokenFulfillmentOutcome.failed(error(retryable: true)),
            .failed(error(retryable: false)),
            .unavailable(error(retryable: true)),
            .pending
        ] {
            await checkRecovery(after: first)
        }
        await checkTerminal(.rejected(error(retryable: false)), credited: false)
        await checkTerminal(.credited(balance), credited: true)
        await checkTerminal(.alreadyCredited(balance), credited: true)
        await checkClearFailure()
        print(
            "Token fulfillment passed: recoverable failures, same evidence and attempt, no second purchase, terminal rejection, credit and clear failure."
        )
    }

    private static func checkRecovery(after first: TokenFulfillmentOutcome) async {
        let fixture = Fixture(outcomes: [first, .credited(balance)])
        let initial = await fixture.manager().purchase(fixture.selection)
        switch first {
        case let .failed(error), let .unavailable(error):
            expect(initial == .failed(error), "initial error is preserved")
        case .pending:
            expect(initial == .pending, "pending stays pending")
        default:
            fatalError("Unexpected recovery fixture")
        }
        guard case let .pending(intent) = await fixture.store.state() else {
            fatalError("Recoverable outcomes must retain pending evidence")
        }
        expect(intent.evidence != nil, "verified evidence is saved before fulfillment")
        await expect(fixture.gate.isFinancialOperationBlocked(), "pending blocks other financial operations")
        await expect(fixture.gate.acquire(.purchase) == nil, "subscription purchase cannot bypass token pending")
        _ = await fixture.manager().purchase(fixture.selection)
        await expect(fixture.provider.calls == 1, "a second tap cannot start another provider purchase")

        // Recompose the manager as a host does on foreground/recovery. The same
        // store owns the attempt; the manager must not request new SDK evidence.
        let restored = await fixture.manager().recoverPendingPurchase()
        expect(restored == .credited(balance), "recovery confirms the original credit")
        let requests = await fixture.fulfillment.requests
        expect(requests.count == 2 && requests[0] == requests[1], "retry reuses the exact attempt and evidence")
        expect(requests[0].attemptID == intent.attemptID, "fulfillment uses the saved attempt")
        await expect(fixture.provider.calls == 1, "recovery never purchases again")
        await expect(fixture.evidence.calls == 1, "recovery uses saved evidence")
        await expect(!(fixture.gate.isFinancialOperationBlocked()), "confirmed credit releases the gate")
        await expect(fixture.manager().recoverPendingPurchase() == nil, "completed attempt is cleared")
    }

    private static func checkTerminal(_ first: TokenFulfillmentOutcome, credited: Bool) async {
        let fixture = Fixture(outcomes: [first])
        let result = await fixture.manager().purchase(fixture.selection)
        if credited {
            expect(result == .credited(balance), "credited and alreadyCredited expose the confirmed balance")
        } else {
            expect(result == .failed(error(retryable: false)), "terminal rejection returns its error")
        }
        await expect(fixture.manager().recoverPendingPurchase() == nil, "terminal result clears the attempt")
        await expect(fixture.fulfillment.requests.count == 1, "terminal result is not retried")
        await expect(!(fixture.gate.isFinancialOperationBlocked()), "terminal result releases the gate")
        guard let lease = await fixture.gate.acquire(.purchase) else {
            fatalError("The next financial operation must be available")
        }
        await fixture.gate.release(lease)
    }

    private static func checkClearFailure() async {
        let fixture = Fixture(outcomes: [.rejected(error(retryable: false))])
        let store = FailingClearStore(base: fixture.store)
        let manager = fixture.manager(store: store)
        let result = await manager.purchase(fixture.selection)
        guard case let .failed(error) = result else { fatalError("Failed persistence must not look complete") }
        expect(error.diagnosticCode == "monetization.tokens.fulfillment-unavailable", "clear failure stays recoverable")
        await expect(fixture.gate.isFinancialOperationBlocked(), "clear failure retains the pending blocker")
        _ = await manager.recoverPendingPurchase()
        let requests = await fixture.fulfillment.requests
        expect(requests.count == 2 && requests[0] == requests[1], "failed clear retains exact evidence for reconciliation")
        await expect(fixture.provider.calls == 1, "failed clear does not repeat purchase")
    }

    private static func error(retryable: Bool) -> AppError {
        AppError(kind: .server, userMessage: "Fixture fulfillment result", diagnosticCode: "fixture.tokens.backend", isRetryable: retryable)
    }

    private static func expect(_ condition: Bool, _ message: String) {
        guard condition else { fatalError("Token contract violation: \(message)") }
    }
}

private struct Fixture {
    let store = InMemoryPendingTokenPurchaseStore()
    let gate = MonetizationOperationGate()
    let provider = FixturePurchaseRepository()
    let evidence = FixtureEvidenceProvider()
    let fulfillment: FixtureFulfillmentRepository
    let selection: ProductSelection

    init(outcomes: [TokenFulfillmentOutcome]) {
        fulfillment = FixtureFulfillmentRepository(outcomes: outcomes)
        let product = MonetizationProduct(
            presentationID: .generated(), reference: ProductReference(rawValue: "fixture-product"),
            productID: ProductID(rawValue: "fixture.tokens"), kind: .consumable,
            price: Money(amount: 1, currencyCode: "USD"), catalogSource: .adapty
        )
        let paywall = PaywallPayload(
            presentationID: .generated(), paywallReference: PaywallReference(rawValue: "fixture-paywall"),
            origin: PaywallOrigin(requestedPlacementID: .tokens, resolvedPlacementID: .tokens, catalogSource: .adapty),
            products: [product], fetchedAt: Date()
        )
        selection = ProductSelection(paywall: paywall, product: product)
    }

    func manager(store override: (any PendingTokenPurchaseStoreProtocol)? = nil) -> TokenPurchaseManager {
        TokenPurchaseManager(
            purchaseRepository: provider, evidenceProvider: evidence,
            fulfillmentRepository: fulfillment, pendingStore: override ?? store, operationGate: gate
        )
    }
}

private actor FixturePurchaseRepository: PurchaseRepositoryProtocol {
    private(set) var calls = 0

    func purchase(_ request: PurchaseRequest) async -> PurchaseAttemptOutcome {
        calls += 1
        return .completed(PurchaseConfirmation(
            productID: request.selection.product.productID, checkoutMethod: .apple, confirmedAt: Date()
        ))
    }
}

private actor FixtureEvidenceProvider: TokenTransactionEvidenceProviderProtocol {
    private(set) var calls = 0

    func evidence(productID: ProductID, purchasedAfter: Date) async -> TokenEvidenceResolution {
        calls += 1
        return .verified(TokenTransactionEvidence(
            transactionID: "fixture-transaction", productID: productID,
            signedTransaction: "fixture-evidence", purchasedAt: purchasedAfter
        ))
    }
}

private actor FixtureFulfillmentRepository: TokenFulfillmentRepositoryProtocol {
    let outcomes: [TokenFulfillmentOutcome]
    private(set) var requests: [TokenFulfillmentRequest] = []

    init(outcomes: [TokenFulfillmentOutcome]) {
        self.outcomes = outcomes
    }

    func fulfill(_ request: TokenFulfillmentRequest) async -> TokenFulfillmentOutcome {
        requests.append(request)
        return outcomes[min(requests.count - 1, outcomes.count - 1)]
    }
}

private struct FailingClearStore: PendingTokenPurchaseStoreProtocol {
    let base: InMemoryPendingTokenPurchaseStore
    var pendingOperationBlockerKey: PendingOperationBlockerKey {
        base.pendingOperationBlockerKey
    }

    func begin(context: PurchaseAnalyticsContext) async -> Bool {
        await base.begin(context: context)
    }

    func state() async -> PendingTokenPurchaseState {
        await base.state()
    }

    func save(evidence: TokenTransactionEvidence, attemptID: MonetizationAttemptID) async -> Bool {
        await base.save(evidence: evidence, attemptID: attemptID)
    }

    func clear(attemptID _: MonetizationAttemptID) async -> Bool {
        false
    }
}
