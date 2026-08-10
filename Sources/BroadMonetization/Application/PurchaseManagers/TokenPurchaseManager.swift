import BroadCore

/// Independent consumable flow for apps that sell tokens. It can be composed
/// next to `SubscriptionPurchaseManager`, but neither manager imports or owns
/// the other one.
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
        let providerOutcome = await purchaseRepository.purchase(
            PurchaseRequest(selection: selection, checkoutMethod: method)
        )
        let outcome = await resolveProviderOutcome(
            providerOutcome,
            context: context
        )
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
                return .failed(unavailableError)
            }
            return await resolve(intent)
        }
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
            await analytics.track(.purchasePending(context))
            await operationGate.notifyFinancialOperationStateChanged()
            return .pending
        case let .failed(error, disposition):
            guard disposition == .definitivelyNotPurchased else {
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
        case .completed:
            switch await pendingStore.state() {
            case let .pending(intent):
                return await resolve(intent)
            case .none, .unavailable:
                return .failed(unavailableError)
            }
        }
    }

    func resolve(_ intent: PendingTokenPurchaseIntent) async -> TokenPurchaseOutcome {
        let evidence: TokenTransactionEvidence
        if let savedEvidence = intent.evidence {
            evidence = savedEvidence
        } else {
            switch await evidenceProvider.evidence(
                productID: intent.productID,
                purchasedAfter: intent.startedAt
            ) {
            case let .verified(resolvedEvidence):
                guard await pendingStore.save(
                    evidence: resolvedEvidence,
                    attemptID: intent.attemptID
                ) else {
                    return .failed(unavailableError)
                }
                evidence = resolvedEvidence
            case .notFound:
                await analytics.track(.purchasePending(intent.analyticsContext))
                return .pending
            case .unavailable:
                return .failed(unavailableError)
            }
        }

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
            await analytics.track(.purchasePending(intent.analyticsContext))
            return .pending
        case let .unavailable(error), let .failed(error):
            await analytics.track(
                .purchaseCompletedButUnverified(intent.analyticsContext)
            )
            return .failed(error)
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
