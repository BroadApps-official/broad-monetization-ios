import BroadCore

/// Independent consumable flow for apps that sell tokens. It can be composed
/// next to `SubscriptionPurchaseManager`, but neither manager imports or owns
/// the other one.
///
/// A pending intent survives only while the outcome is still open: a purchase
/// whose evidence has not appeared yet, or a backend that could not answer.
/// Only an explicit `TokenFulfillmentOutcome.rejected` ends a refused attempt
/// and releases the pending store, a blocker of the shared operation gate.
/// Legacy `.failed` responses keep their evidence for reconciliation.
public actor TokenPurchaseManager {
    private let purchaseRepository: any PurchaseRepositoryProtocol
    private let evidenceProvider: any TokenTransactionEvidenceProviderProtocol
    private let fulfillmentRepository: any TokenFulfillmentRepositoryProtocol
    private let pendingStore: any PendingTokenPurchaseStoreProtocol
    private let analytics: any MonetizationAnalyticsProtocol
    private let operationGate: MonetizationOperationGate
    private let inProgressError: AppError
    private let unavailableError: AppError
    private let unsupportedProductError: AppError
    private var activeProviderAttemptID: MonetizationAttemptID?

    public init(
        purchaseRepository: any PurchaseRepositoryProtocol,
        evidenceProvider: any TokenTransactionEvidenceProviderProtocol,
        fulfillmentRepository: any TokenFulfillmentRepositoryProtocol,
        pendingStore: any PendingTokenPurchaseStoreProtocol,
        analytics: any MonetizationAnalyticsProtocol = NoOpMonetizationAnalytics(),
        operationGate: MonetizationOperationGate,
        inProgressError: AppError? = nil,
        unavailableError: AppError? = nil,
        unsupportedProductError: AppError? = nil
    ) {
        self.purchaseRepository = purchaseRepository
        self.evidenceProvider = evidenceProvider
        self.fulfillmentRepository = fulfillmentRepository
        self.pendingStore = pendingStore
        self.analytics = NonBlockingMonetizationAnalytics.wrapping(analytics)
        self.operationGate = operationGate
        self.inProgressError = inProgressError ?? Self.defaultInProgressError
        self.unavailableError = unavailableError ?? Self.defaultUnavailableError
        self.unsupportedProductError = unsupportedProductError
            ?? Self.defaultUnsupportedProductError
        operationGate.registerPendingOperationBlocker(pendingStore)
        StoreEvidenceConsumerRegistry.shared.register(
            self,
            for: pendingStore.pendingOperationBlockerKey
        )
    }

    public func purchase(
        _ selection: ProductSelection,
        using method: CheckoutMethod = .apple
    ) async -> TokenPurchaseOutcome {
        guard selection.product.kind == .consumable,
              selection.product.price != nil,
              method == .apple
        else {
            return .failed(unsupportedProductError)
        }
        guard let lease = await operationGate.acquire(.tokenPurchase) else {
            return .failed(inProgressError)
        }

        let context = PurchaseAnalyticsContext(
            attemptID: .generated(),
            selection: selection,
            checkoutMethod: method
        )
        guard await pendingStore.begin(context: context) else {
            await operationGate.release(lease)
            return .failed(unavailableError)
        }

        await analytics.track(.purchaseStarted(context))
        activeProviderAttemptID = context.attemptID
        let providerOutcome = await purchaseRepository.purchase(
            PurchaseRequest(selection: selection, checkoutMethod: method)
        )
        let providerMayHaveRacedWithUpdate = switch providerOutcome {
        case .pending, .failed(_, .outcomeUnknown):
            true
        case .cancelled, .completed, .failed(_, .definitivelyNotPurchased):
            false
        }
        var outcome = await resolveProviderOutcome(
            providerOutcome,
            context: context
        )
        if providerMayHaveRacedWithUpdate,
           outcome == .pending,
           case let .pending(intent) = await pendingStore.state(),
           intent.evidence != nil {
            // The updates bridge may have persisted evidence while the provider
            // was still returning `.pending` or an unknown outcome.
            outcome = await resolve(intent)
        }
        if activeProviderAttemptID == context.attemptID {
            activeProviderAttemptID = nil
        }
        await operationGate.release(lease)
        return outcome
    }

    /// Call on launch and after returning to the foreground. A saved verified
    /// transaction is retried against the app backend without charging again.
    public func recoverPendingPurchase() async -> TokenPurchaseOutcome? {
        switch await pendingStore.state() {
        case .none:
            return nil
        case .unavailable:
            return .failed(unavailableError)
        case let .pending(intent):
            guard intent.belongsToCurrentSubject else {
                await pendingStore.noteDiagnostic(
                    attemptID: intent.attemptID,
                    stage: .accountMismatch,
                    diagnosticCode: nil
                )
                return .failed(unavailableError)
            }
            return await resolve(intent)
        }
    }
}

extension TokenPurchaseManager: StoreEvidenceConsumer {
    func receiveCapturedStoreTransactionEvidence(
        _ capturedEvidence: CapturedStoreTransactionEvidence
    ) async -> Bool {
        guard case let .pending(intent) = await pendingStore.state(),
              intent.belongsToCurrentSubject,
              intent.productID.rawValue == capturedEvidence.productID
        else {
            return false
        }

        let evidence: TokenTransactionEvidence
        if let savedEvidence = intent.evidence {
            guard savedEvidence.transactionID == capturedEvidence.transactionID else {
                return false
            }
            evidence = savedEvidence
        } else {
            guard let capturedEvidenceProvider = evidenceProvider
                as? any DirectTokenEvidenceProvider,
                case let .verified(resolvedEvidence) = await capturedEvidenceProvider.evidence(
                    from: capturedEvidence,
                    productID: intent.productID,
                    purchasedAfter: intent.startedAt
                ),
                await pendingStore.save(
                    evidence: resolvedEvidence,
                    attemptID: intent.attemptID
                )
            else {
                return false
            }
            evidence = resolvedEvidence
        }

        // The interactive purchase call consumes the same saved evidence when
        // Adapty returns. Out-of-band approvals have no such caller, so finish
        // their idempotent backend fulfillment directly from the update bridge.
        guard activeProviderAttemptID != intent.attemptID else {
            return true
        }
        _ = await fulfill(evidence, for: intent)
        return true
    }
}

private extension TokenPurchaseManager {
    func resolveProviderOutcome(
        _ outcome: PurchaseAttemptOutcome,
        context: PurchaseAnalyticsContext
    ) async -> TokenPurchaseOutcome {
        switch outcome {
        case .cancelled:
            return await clearAndReturn(
                .cancelled,
                context: context,
                event: .purchaseCancelled(context)
            )
        case .pending:
            await pendingStore.noteDiagnostic(
                attemptID: context.attemptID,
                stage: .providerPending,
                diagnosticCode: nil
            )
            await analytics.track(.purchasePending(context))
            await operationGate.notifyFinancialOperationStateChanged()
            return .pending
        case let .failed(error, disposition):
            guard disposition == .definitivelyNotPurchased else {
                await pendingStore.noteDiagnostic(
                    attemptID: context.attemptID,
                    stage: .outcomeUnknown,
                    diagnosticCode: error.diagnosticCode
                )
                await analytics.track(.purchasePending(context))
                await operationGate.notifyFinancialOperationStateChanged()
                return .pending
            }
            return await clearAndReturn(
                .failed(error),
                context: context,
                event: .purchaseFailed(
                    context,
                    failure: MonetizationAnalyticsFailure(error: error)
                )
            )
        case let .completed(confirmation):
            switch await pendingStore.state() {
            case let .pending(intent):
                return await resolve(
                    intent,
                    capturedEvidence: confirmation.takeCapturedStoreTransactionEvidence()
                )
            case .none, .unavailable:
                return .failed(unavailableError)
            }
        }
    }

    func resolve(
        _ intent: PendingTokenPurchaseIntent,
        capturedEvidence: CapturedStoreTransactionEvidence? = nil
    ) async -> TokenPurchaseOutcome {
        let evidence: TokenTransactionEvidence
        if let savedEvidence = intent.evidence {
            evidence = savedEvidence
        } else {
            let resolution: TokenEvidenceResolution = if let capturedEvidence,
                                                         let capturedEvidenceProvider = evidenceProvider
                                                         as? any DirectTokenEvidenceProvider {
                await capturedEvidenceProvider.evidence(
                    from: capturedEvidence,
                    productID: intent.productID,
                    purchasedAfter: intent.startedAt
                )
            } else {
                await evidenceProvider.evidence(
                    productID: intent.productID,
                    purchasedAfter: intent.startedAt
                )
            }
            switch resolution {
            case let .verified(resolvedEvidence):
                guard await pendingStore.save(
                    evidence: resolvedEvidence,
                    attemptID: intent.attemptID
                ) else {
                    return .failed(unavailableError)
                }
                evidence = resolvedEvidence
            case .notFound:
                await pendingStore.noteDiagnostic(
                    attemptID: intent.attemptID,
                    stage: .transactionNotFound,
                    diagnosticCode: nil
                )
                await analytics.track(.purchasePending(intent.analyticsContext))
                return .pending
            case .unavailable:
                await pendingStore.noteDiagnostic(
                    attemptID: intent.attemptID,
                    stage: .storeUnavailable,
                    diagnosticCode: nil
                )
                return .failed(unavailableError)
            }
        }

        return await fulfill(evidence, for: intent)
    }

    /// The intent is released only when the outcome is settled: credited, or
    /// refused for good. Anything still open keeps it for the next attempt.
    func fulfill(
        _ evidence: TokenTransactionEvidence,
        for intent: PendingTokenPurchaseIntent
    ) async -> TokenPurchaseOutcome {
        let fulfillment = await fulfillmentRepository.fulfill(
            TokenFulfillmentRequest(
                attemptID: intent.attemptID,
                evidence: evidence
            )
        )
        switch fulfillment {
        case let .credited(balance), let .alreadyCredited(balance):
            guard await pendingStore.clear(attemptID: intent.attemptID) else {
                return .failed(unavailableError)
            }
            await operationGate.notifyFinancialOperationStateChanged()
            await analytics.track(.purchaseSuccess(intent.analyticsContext))
            return .credited(balance)
        case .pending:
            await pendingStore.noteDiagnostic(
                attemptID: intent.attemptID,
                stage: .backendPending,
                diagnosticCode: nil
            )
            await analytics.track(.purchasePending(intent.analyticsContext))
            return .pending
        case let .unavailable(error), let .failed(error):
            await pendingStore.noteDiagnostic(
                attemptID: intent.attemptID,
                stage: .backendUnavailable,
                diagnosticCode: error.diagnosticCode
            )
            // Neither outcome proves a terminal refusal. Preserve evidence
            // even when the AppError UI retry hint is false.
            await analytics.track(
                .purchaseCompletedButUnverified(intent.analyticsContext)
            )
            return .failed(error)
        case let .rejected(error):
            // The adapter explicitly establishes financial finality. Clear
            // only this attempt and release the shared gate after durable success.
            return await clearAndReturn(
                .failed(error),
                context: intent.analyticsContext,
                event: .purchaseCompletedButUnverified(intent.analyticsContext)
            )
        }
    }

    func clearAndReturn(
        _ outcome: TokenPurchaseOutcome,
        context: PurchaseAnalyticsContext,
        event: MonetizationAnalyticsEvent
    ) async -> TokenPurchaseOutcome {
        guard await pendingStore.clear(attemptID: context.attemptID) else {
            return .failed(unavailableError)
        }
        await operationGate.notifyFinancialOperationStateChanged()
        await analytics.track(event)
        return outcome
    }

    static let defaultInProgressError = AppError(
        kind: .unavailable,
        userMessage: "Another payment is already in progress.",
        diagnosticCode: "monetization.tokens.in-progress",
        isRetryable: false
    )

    static let defaultUnavailableError = AppError(
        kind: .unavailable,
        userMessage: "The token purchase is waiting for confirmation.",
        diagnosticCode: "monetization.tokens.fulfillment-unavailable",
        isRetryable: true
    )

    static let defaultUnsupportedProductError = AppError(
        kind: .unavailable,
        userMessage: "This token pack is temporarily unavailable.",
        diagnosticCode: "monetization.tokens.unsupported-product",
        isRetryable: false
    )
}
