import BroadCore
import Foundation

@main
enum TokenPurchaseProbe {
    private static let balance = TokenBalanceSnapshot(balance: 2000, updatedAt: Date())

    static func main() async {
        checkPurchaseConfirmationCompatibility()
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
        await checkOutOfBandApproval()
        await checkUpdateWhileProviderReturnsPending()
        await checkBufferedOutOfBandApproval()
        print(
            "Token fulfillment passed: direct JWS handoff, live and buffered out-of-band approval, recoverable failures, same evidence and attempt, no second purchase, terminal rejection, credit and clear failure."
        )
    }

    private static func checkPurchaseConfirmationCompatibility() {
        let productID = ProductID(rawValue: "fixture.tokens")
        let confirmedAt = Date()
        let publicConfirmation = PurchaseConfirmation(
            productID: productID,
            checkoutMethod: .apple,
            confirmedAt: confirmedAt
        )
        let capturedConfirmation = PurchaseConfirmation(
            productID: productID,
            checkoutMethod: .apple,
            confirmedAt: confirmedAt,
            capturedStoreTransactionEvidence: capturedEvidence(productID: productID)
        )
        expect(capturedConfirmation == publicConfirmation, "internal evidence does not change public equality")

        do {
            let encoded = try JSONEncoder().encode(capturedConfirmation)
            let json = String(decoding: encoded, as: UTF8.self)
            expect(!json.contains("fixture-evidence"), "public encoding excludes signed evidence")
            let decoded = try JSONDecoder().decode(
                PurchaseConfirmation.self,
                from: encoded
            )
            expect(decoded == publicConfirmation, "public confirmation Codable shape stays compatible")
        } catch {
            fatalError("Token contract violation: purchase confirmation Codable failed")
        }
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
        await expect(fixture.evidence.historyCalls == 0, "direct JWS never depends on transaction history")
        await expect(fixture.evidence.capturedCalls == 1, "recovery uses saved direct evidence")
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

    private static func checkOutOfBandApproval() async {
        let fixture = Fixture(outcomes: [.credited(balance)], providerMode: .pending)
        let manager = fixture.manager()
        let initial = await manager.purchase(fixture.selection)
        expect(initial == .pending, "provider-pending purchase remains open")
        await expect(fixture.gate.isFinancialOperationBlocked(), "out-of-band approval starts from a durable blocker")

        _ = await manager.receiveCapturedStoreTransactionEvidence(
            capturedEvidence(productID: fixture.selection.product.productID)
        )

        await expect(fixture.fulfillment.requests.count == 1, "transaction update triggers fulfillment")
        await expect(fixture.evidence.historyCalls == 0, "transaction update does not scan finished history")
        await expect(fixture.evidence.capturedCalls == 1, "transaction update validates captured JWS")
        await expect(fixture.store.state() == .none, "credited out-of-band purchase clears pending state")
        await expect(!(fixture.gate.isFinancialOperationBlocked()), "credited out-of-band purchase releases the gate")
    }

    private static func checkUpdateWhileProviderReturnsPending() async {
        let fixture = Fixture(
            outcomes: [.credited(balance)],
            providerMode: .pendingWithTransactionUpdate
        )
        let result = await fixture.manager().purchase(fixture.selection)

        expect(result == .credited(balance), "captured update outranks a racing provider-pending result")
        await expect(fixture.fulfillment.requests.count == 1, "racing update fulfills exactly once")
        await expect(fixture.evidence.historyCalls == 0, "racing update does not scan history")
        await expect(fixture.evidence.capturedCalls == 1, "racing update validates captured JWS")
        await expect(!(fixture.gate.isFinancialOperationBlocked()), "racing update releases the gate")
    }

    private static func checkBufferedOutOfBandApproval() async {
        let fixture = Fixture(outcomes: [.credited(balance)])
        let context = PurchaseAnalyticsContext(
            attemptID: .generated(),
            selection: fixture.selection,
            checkoutMethod: .apple
        )
        await expect(fixture.store.begin(context: context), "fixture persists the pending approval")

        let evidence = capturedEvidence(
            transactionID: "fixture-buffered-transaction",
            productID: fixture.selection.product.productID
        )
        _ = StoreEvidenceConsumerRegistry.shared.publish(
            evidence
        )

        let manager = fixture.manager()
        var fulfilled = false
        for _ in 0 ..< 1000 {
            if await fixture.fulfillment.requests.count == 1 {
                fulfilled = true
                break
            }
            await Task.yield()
        }

        expect(fulfilled, "a transaction buffered before manager composition is fulfilled")
        await expect(fixture.store.state() == .none, "buffered approval clears pending state")
        await expect(fixture.evidence.historyCalls == 0, "buffered approval does not scan history")
        await expect(fixture.evidence.capturedCalls == 1, "buffered approval validates captured JWS")
        await expect(!(fixture.gate.isFinancialOperationBlocked()), "buffered approval releases the gate")
        withExtendedLifetime(manager) {}
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
    let provider: FixturePurchaseRepository
    let evidence = FixtureEvidenceProvider()
    let fulfillment: FixtureFulfillmentRepository
    let selection: ProductSelection

    init(
        outcomes: [TokenFulfillmentOutcome],
        providerMode: FixturePurchaseMode = .completed
    ) {
        fulfillment = FixtureFulfillmentRepository(outcomes: outcomes)
        provider = FixturePurchaseRepository(mode: providerMode)
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

private enum FixturePurchaseMode {
    case completed
    case pending
    case pendingWithTransactionUpdate
}

private actor FixturePurchaseRepository: PurchaseRepositoryProtocol {
    private let mode: FixturePurchaseMode
    private(set) var calls = 0

    init(mode: FixturePurchaseMode) {
        self.mode = mode
    }

    func purchase(_ request: PurchaseRequest) async -> PurchaseAttemptOutcome {
        calls += 1
        switch mode {
        case .pending:
            return .pending
        case .pendingWithTransactionUpdate:
            let evidence = capturedEvidence(
                transactionID: "fixture-racing-transaction",
                productID: request.selection.product.productID
            )
            let registry = StoreEvidenceConsumerRegistry.shared
            for consumer in registry.publish(evidence) {
                if await consumer.receiveCapturedStoreTransactionEvidence(evidence) {
                    registry.discard(transactionID: evidence.transactionID)
                    break
                }
            }
            return .pending
        case .completed:
            return .completed(PurchaseConfirmation(
                productID: request.selection.product.productID,
                checkoutMethod: .apple,
                confirmedAt: Date(),
                capturedStoreTransactionEvidence: capturedEvidence(
                    productID: request.selection.product.productID
                )
            ))
        }
    }
}

private actor FixtureEvidenceProvider:
    TokenTransactionEvidenceProviderProtocol,
    DirectTokenEvidenceProvider {
    private(set) var historyCalls = 0
    private(set) var capturedCalls = 0

    func evidence(productID: ProductID, purchasedAfter: Date) async -> TokenEvidenceResolution {
        historyCalls += 1
        return .verified(TokenTransactionEvidence(
            transactionID: "fixture-transaction", productID: productID,
            signedTransaction: "fixture-evidence", purchasedAt: purchasedAfter
        ))
    }

    func evidence(
        from captured: CapturedStoreTransactionEvidence,
        productID: ProductID,
        purchasedAfter _: Date
    ) async -> TokenEvidenceResolution {
        capturedCalls += 1
        return .verified(TokenTransactionEvidence(
            transactionID: captured.transactionID,
            productID: productID,
            signedTransaction: captured.signedTransaction,
            purchasedAt: captured.purchasedAt
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

private func capturedEvidence(
    transactionID: String = "fixture-transaction",
    productID: ProductID
) -> CapturedStoreTransactionEvidence {
    CapturedStoreTransactionEvidence(
        transactionID: transactionID,
        productID: productID.rawValue,
        signedTransaction: "fixture-evidence",
        purchasedAt: Date(),
        appBundleIdentifier: "dev.broadapps.fixture",
        appAccountToken: nil,
        isConsumable: true,
        isPurchase: true,
        revocationDate: nil,
        isUpgraded: false
    )
}
