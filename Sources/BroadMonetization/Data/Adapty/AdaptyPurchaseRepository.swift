import Adapty
import BroadCore
import StoreKit

public actor AdaptyPurchaseRepository: PurchaseRepositoryProtocol {
    private let configuration: AdaptyPlatformConfiguration
    private let identityProvider: any AdaptyIdentityProviderProtocol
    private let context: AdaptyRepositoryContext
    private let paywallRepository: any PaywallRepositoryProtocol
    private let messages: AdaptyMonetizationMessages
    private let clock: CacheClock

    private var isPurchasing = false

    public init(
        configuration: AdaptyPlatformConfiguration,
        identityProvider: any AdaptyIdentityProviderProtocol,
        context: AdaptyRepositoryContext,
        paywallRepository: any PaywallRepositoryProtocol,
        messages: AdaptyMonetizationMessages,
        clock: CacheClock = .system
    ) {
        self.configuration = configuration
        self.identityProvider = identityProvider
        self.context = context
        self.paywallRepository = paywallRepository
        self.messages = messages
        self.clock = clock
    }

    public func purchase(
        _ request: PurchaseRequest
    ) async -> PurchaseAttemptOutcome {
        guard request.checkoutMethod == .apple else {
            return definitiveFailure(productUnavailableError())
        }
        guard !isPurchasing else {
            return definitiveFailure(purchaseInProgressError())
        }

        isPurchasing = true
        defer { isPurchasing = false }

        guard let resolvedProduct = await resolveProduct(for: request.selection) else {
            return definitiveFailure(productUnavailableError())
        }
        guard !Task.isCancelled else {
            if let temporaryPresentation = resolvedProduct.temporaryPresentation {
                await release(temporaryPresentation)
            }
            return definitiveFailure(productUnavailableError())
        }

        let activationOutcome = await AdaptySDKActivationGate.shared.perform(
            configuration: configuration,
            identityProvider: identityProvider,
            compositionID: context.sdkCompositionID,
            operation: { [self] in
                await purchaseUnderLease(resolvedProduct.product, request: request)
            }
        )
        if let temporaryPresentation = resolvedProduct.temporaryPresentation {
            await release(temporaryPresentation)
        }
        guard let outcome = activationOutcome else {
            return definitiveFailure(activationError())
        }
        return outcome
    }
}

private extension AdaptyPurchaseRepository {
    struct ResolvedProduct {
        let product: any AdaptyPaywallProduct
        let temporaryPresentation: PaywallPayload?
    }

    func purchaseUnderLease(
        _ product: any AdaptyPaywallProduct,
        request: PurchaseRequest
    ) async -> PurchaseAttemptOutcome {
        do {
            let result = try await Adapty.makePurchase(product: product)

            switch result {
            case .userCancelled:
                return .cancelled
            case .pending:
                return .pending
            case .success:
                return completedOutcome(result, request: request)
            }
        } catch {
            return .failed(
                purchaseUnavailableError(),
                disposition: .outcomeUnknown
            )
        }
    }

    func completedOutcome(
        _ result: AdaptyPurchaseResult,
        request: PurchaseRequest
    ) -> PurchaseAttemptOutcome {
        let confirmationDate = clock.now()
        guard request.selection.product.kind == .consumable else {
            return .completed(
                PurchaseConfirmation(
                    productID: request.selection.product.productID,
                    checkoutMethod: .apple,
                    confirmedAt: confirmationDate
                )
            )
        }

        // Adapty returns StoreKit's verified transaction and JWS even though
        // its default auto-finish mode has already removed the consumable from
        // Transaction.all on iOS 17. Hand it directly to TokenPurchaseManager.
        guard let capturedEvidence = StoreKitTransactionEvidenceCapture.capture(
            result.sk2SignedTransaction
        ) else {
            return .failed(
                purchaseUnavailableError(),
                disposition: .outcomeUnknown
            )
        }
        return .completed(
            PurchaseConfirmation(
                productID: request.selection.product.productID,
                checkoutMethod: .apple,
                confirmedAt: confirmationDate,
                capturedStoreTransactionEvidence: capturedEvidence
            )
        )
    }

    func resolveProduct(
        for selection: ProductSelection
    ) async -> ResolvedProduct? {
        if let product = await context.productRegistry.product(for: selection) {
            return ResolvedProduct(
                product: product,
                temporaryPresentation: nil
            )
        }

        let outcome = await paywallRepository.loadPaywall(
            for: selection.resolvedPlacementID
        )
        guard case let .loaded(paywall) = outcome else {
            return nil
        }
        guard paywall.origin.catalogSource == .adapty,
              paywall.variationID == selection.paywallVariationID,
              paywall.products.indices.contains(selection.productIndex)
        else {
            await release(paywall)
            return nil
        }

        let rehydratedProduct = paywall.products[selection.productIndex]
        guard let expectedFingerprint = selection.product.commercialFingerprint,
              rehydratedProduct.productID == selection.product.productID,
              rehydratedProduct.commercialFingerprint == expectedFingerprint
        else {
            await release(paywall)
            return nil
        }

        let rehydratedSelection = ProductSelection(
            paywall: paywall,
            product: rehydratedProduct
        )
        guard let product = await context.productRegistry.product(
            for: rehydratedSelection
        ) else {
            await release(paywall)
            return nil
        }
        return ResolvedProduct(
            product: product,
            temporaryPresentation: paywall
        )
    }

    func release(_ paywall: PaywallPayload) async {
        await context.productRegistry.release(
            presentationID: paywall.presentationID,
            reference: paywall.paywallReference
        )
    }

    func activationError() -> AppError {
        AppError(
            kind: .unavailable,
            userMessage: messages.activationUnavailable,
            diagnosticCode: "monetization.adapty.purchase-activation-unavailable",
            isRetryable: true
        )
    }

    func productUnavailableError() -> AppError {
        AppError(
            kind: .unavailable,
            userMessage: messages.productUnavailable,
            diagnosticCode: "monetization.adapty.product-reference-unavailable",
            isRetryable: true
        )
    }

    func purchaseInProgressError() -> AppError {
        AppError(
            kind: .unavailable,
            userMessage: messages.purchaseFailed,
            diagnosticCode: "monetization.adapty.purchase-in-progress",
            isRetryable: false
        )
    }

    func purchaseUnavailableError() -> AppError {
        AppError(
            kind: .unavailable,
            userMessage: messages.purchaseFailed,
            diagnosticCode: "monetization.adapty.purchase-failed",
            isRetryable: true
        )
    }

    func definitiveFailure(_ error: AppError) -> PurchaseAttemptOutcome {
        .failed(error, disposition: .definitivelyNotPurchased)
    }
}
