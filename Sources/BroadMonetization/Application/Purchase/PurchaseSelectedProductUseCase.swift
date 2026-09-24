import BroadCore

public actor PurchaseSelectedProductUseCase: PurchaseSelectedProductUseCaseProtocol {
    private let repository: any PurchaseRepositoryProtocol
    private let entitlementRepository: any EntitlementRepositoryProtocol
    private let analytics: any MonetizationAnalyticsProtocol
    private let pendingStore: any PendingApplePurchaseStoreProtocol
    public nonisolated let monetizationOperationGate: MonetizationOperationGate
    private let inProgressError: AppError
    private let pendingStateUnavailableError: AppError
    private let unsupportedProductError: AppError
    private let premiumProductCatalog: ApplePremiumProductCatalog?

    public init(
        repository: any PurchaseRepositoryProtocol,
        entitlementRepository: any EntitlementRepositoryProtocol,
        analytics: any MonetizationAnalyticsProtocol,
        pendingStore: any PendingApplePurchaseStoreProtocol,
        operationGate: MonetizationOperationGate,
        inProgressError: AppError,
        pendingStateUnavailableError: AppError? = nil,
        unsupportedProductError: AppError? = nil
    ) {
        self.init(
            repository: repository,
            entitlementRepository: entitlementRepository,
            analytics: analytics,
            pendingStore: pendingStore,
            operationGate: operationGate,
            inProgressError: inProgressError,
            pendingStateUnavailableError: pendingStateUnavailableError,
            unsupportedProductError: unsupportedProductError,
            premiumProductCatalog: nil
        )
    }

    public init(
        repository: any PurchaseRepositoryProtocol,
        entitlementRepository: any EntitlementRepositoryProtocol,
        analytics: any MonetizationAnalyticsProtocol,
        pendingStore: any PendingApplePurchaseStoreProtocol,
        operationGate: MonetizationOperationGate,
        inProgressError: AppError,
        pendingStateUnavailableError: AppError? = nil,
        unsupportedProductError: AppError? = nil,
        premiumProductCatalog: ApplePremiumProductCatalog?
    ) {
        self.repository = repository
        self.entitlementRepository = entitlementRepository
        self.analytics = NonBlockingMonetizationAnalytics.wrapping(analytics)
        self.pendingStore = pendingStore
        monetizationOperationGate = operationGate
        self.inProgressError = inProgressError
        self.pendingStateUnavailableError = pendingStateUnavailableError
            ?? Self.defaultPendingStateUnavailableError
        self.unsupportedProductError = unsupportedProductError
            ?? Self.defaultUnsupportedProductError
        self.premiumProductCatalog = premiumProductCatalog
        operationGate.registerPendingOperationBlocker(pendingStore)
    }

    public func callAsFunction(
        _ selection: ProductSelection,
        using checkoutMethod: CheckoutMethod
    ) async -> PurchaseOutcome {
        // The generic flow requires a validated Money value and a supported
        // premium product kind. Provider display text is not financial proof,
        // and consumables need a dedicated exactly-once fulfillment boundary.
        // Reject before acquiring the gate, persisting intent or opening the
        // provider sheet.
        guard selection.product.isEligibleForGenericPurchase else {
            return .failed(unsupportedProductError)
        }
        if checkoutMethod == .apple,
           let premiumProductCatalog,
           !Self.isCoveredByPremiumCatalog(
               selection.product,
               catalog: premiumProductCatalog
           ) {
            return .failed(unsupportedProductError)
        }
        guard let lease = await monetizationOperationGate.acquire(.purchase) else {
            return .failed(inProgressError)
        }

        let context = PurchaseAnalyticsContext(
            attemptID: .generated(),
            selection: selection,
            checkoutMethod: checkoutMethod
        )
        guard await pendingStore.begin(
            context: context,
            productKind: selection.product.kind
        ) else {
            await monetizationOperationGate.release(lease)
            return .failed(pendingStateUnavailableError)
        }

        await analytics.track(.purchaseStarted(context))
        let providerOutcome = await performPurchase(
            selection,
            using: checkoutMethod,
            context: context
        )
        let outcome: PurchaseOutcome
        if shouldClearPendingIntent(
            after: providerOutcome,
            productKind: selection.product.kind
        ) {
            let cleared = await pendingStore.clear(attemptID: context.attemptID)
            outcome = resolvedOutcome(
                providerOutcome,
                pendingIntentWasCleared: cleared
            )
        } else {
            outcome = providerOutcome
        }
        await track(outcome, context: context)
        await monetizationOperationGate.release(lease)
        return outcome
    }
}

extension PurchaseSelectedProductUseCase: MonetizationOperationGateProviding {}

private extension PurchaseSelectedProductUseCase {
    static func isCoveredByPremiumCatalog(
        _ product: MonetizationProduct,
        catalog: ApplePremiumProductCatalog
    ) -> Bool {
        guard let entry = catalog.entry(for: product.productID.rawValue) else {
            return false
        }
        switch (product.kind, entry.kind) {
        case (.autoRenewableSubscription, .autoRenewable),
             (.nonConsumable, .nonConsumable),
             (.nonRenewingSubscription, .nonRenewing):
            return true
        default:
            return false
        }
    }

    func performPurchase(
        _ selection: ProductSelection,
        using checkoutMethod: CheckoutMethod,
        context: PurchaseAnalyticsContext
    ) async -> PurchaseOutcome {
        let attempt = await repository.purchase(
            PurchaseRequest(
                selection: selection,
                checkoutMethod: checkoutMethod
            )
        )

        switch attempt {
        case .cancelled:
            return .cancelled
        case .pending:
            await pendingStore.noteDiagnostic(
                attemptID: context.attemptID,
                stage: .providerPending,
                diagnosticCode: nil
            )
            return .pending
        case let .failed(error, disposition):
            if disposition != .definitivelyNotPurchased {
                await pendingStore.noteDiagnostic(
                    attemptID: context.attemptID,
                    stage: .outcomeUnknown,
                    diagnosticCode: error.diagnosticCode
                )
            }
            return disposition == .definitivelyNotPurchased
                ? .failed(error)
                : .pending
        case let .completed(confirmation):
            return await confirmCompleted(
                confirmation,
                selection: selection,
                checkoutMethod: checkoutMethod,
                context: context
            )
        }
    }

    func confirmCompleted(
        _ confirmation: PurchaseConfirmation,
        selection: ProductSelection,
        checkoutMethod: CheckoutMethod,
        context: PurchaseAnalyticsContext
    ) async -> PurchaseOutcome {
        // Persist provider completion before refresh. Unknown and deferred
        // outcomes still require verified StoreKit history.
        if checkoutMethod == .apple,
           selection.product.kind != .consumable {
            _ = await pendingStore.markTransactionConfirmed(
                attemptID: context.attemptID
            )
        }
        await pendingStore.noteDiagnostic(
            attemptID: context.attemptID,
            stage: .transactionVerified,
            diagnosticCode: nil
        )
        let snapshot = await entitlementRepository.refreshEntitlement(
            policy: .startNewGeneration
        )
        guard snapshot.isCurrentActiveConfirmed else {
            await pendingStore.noteDiagnostic(
                attemptID: context.attemptID,
                stage: .entitlementAwaitingConfirmation,
                diagnosticCode: nil
            )
            return .completedButUnverified(confirmation)
        }
        return .activated(snapshot)
    }

    func resolvedOutcome(
        _ outcome: PurchaseOutcome,
        pendingIntentWasCleared: Bool
    ) -> PurchaseOutcome {
        guard !pendingIntentWasCleared else {
            return outcome
        }

        switch outcome {
        case .activated:
            // Access is already authoritative. Keep the durable blocker so no
            // second charge can start; foreground reconciliation retries clear.
            return outcome
        case .cancelled, .failed, .completed, .completedButUnverified:
            return .failed(pendingStateUnavailableError)
        case .pending:
            return outcome
        }
    }

    func track(
        _ outcome: PurchaseOutcome,
        context: PurchaseAnalyticsContext
    ) async {
        switch outcome {
        case .activated:
            await analytics.track(.purchaseSuccess(context))
        case .completed:
            await analytics.track(.purchaseSuccess(context))
        case .completedButUnverified:
            await analytics.track(.purchaseCompletedButUnverified(context))
        case .cancelled:
            await analytics.track(.purchaseCancelled(context))
        case .pending:
            await analytics.track(.purchasePending(context))
        case let .failed(error):
            await analytics.track(
                .purchaseFailed(
                    context,
                    failure: MonetizationAnalyticsFailure(error: error)
                )
            )
        }
    }

    func shouldClearPendingIntent(
        after outcome: PurchaseOutcome,
        productKind: MonetizationProductKind
    ) -> Bool {
        switch outcome {
        case .activated, .completed, .cancelled, .failed:
            true
        case .pending:
            false
        case .completedButUnverified:
            productKind == .consumable
        }
    }

    static let defaultPendingStateUnavailableError = AppError(
        kind: .unavailable,
        userMessage: "Purchases are temporarily unavailable. Please try again.",
        diagnosticCode: "monetization.purchase.pending-state-unavailable",
        isRetryable: true
    )

    static let defaultUnsupportedProductError = AppError(
        kind: .unavailable,
        userMessage: "This product is temporarily unavailable.",
        diagnosticCode: "monetization.purchase.product-not-eligible",
        isRetryable: false
    )
}
