import BroadCore

/// Routes a selected paywall occurrence to the correct provider without exposing
/// SDK, catalog or HTTP details to presentation.
public actor CheckoutSelectedProductUseCase: CheckoutSelectedProductUseCaseProtocol {
    private let applePurchase: any PurchaseSelectedProductUseCaseProtocol
    private let additionalCheckout: (any CheckoutSelectedProductUseCaseProtocol)?
    private let inProgressError: AppError
    private let unsupportedProductError: AppError

    private var isCheckoutInFlight = false

    public init(
        applePurchase: any PurchaseSelectedProductUseCaseProtocol,
        additionalCheckout: (any CheckoutSelectedProductUseCaseProtocol)? = nil,
        inProgressError: AppError? = nil,
        unsupportedProductError: AppError? = nil
    ) {
        self.applePurchase = applePurchase
        self.additionalCheckout = additionalCheckout
        self.inProgressError = inProgressError ?? Self.defaultInProgressError
        self.unsupportedProductError = unsupportedProductError
            ?? Self.defaultUnsupportedProductError
    }

    public func callAsFunction(
        _ selection: ProductSelection,
        using checkoutMethod: CheckoutMethod,
        remoteConfiguration: RemotePaywallConfiguration,
        options: CheckoutOptions
    ) async -> CheckoutSelectedProductOutcome {
        // This is the provider-routing boundary, so direct callers cannot
        // bypass UI validation and reach either any checkout with an
        // unpriced/unsupported generic product.
        guard selection.product.isEligibleForGenericPurchase else {
            return .failed(unsupportedProductError)
        }
        guard !isCheckoutInFlight else {
            return .failed(inProgressError)
        }

        isCheckoutInFlight = true
        defer { isCheckoutInFlight = false }

        switch checkoutMethod {
        case .apple:
            return await map(
                applePurchase(
                    selection,
                    using: .apple
                )
            )
        default:
            guard let additionalCheckout else { return .failed(unsupportedProductError) }
            return await additionalCheckout(selection, using: checkoutMethod, remoteConfiguration: remoteConfiguration, options: options)
        }
    }
}

private extension CheckoutSelectedProductUseCase {
    static let defaultInProgressError = AppError(
        kind: .unavailable,
        userMessage: "Another checkout is already in progress.",
        diagnosticCode: "monetization.checkout.in-progress",
        isRetryable: false
    )

    static let defaultUnsupportedProductError = AppError(
        kind: .unavailable,
        userMessage: "This product is temporarily unavailable.",
        diagnosticCode: "monetization.checkout.product-not-eligible",
        isRetryable: false
    )

    func map(_ outcome: PurchaseOutcome) -> CheckoutSelectedProductOutcome {
        switch outcome {
        case let .activated(snapshot):
            .activated(snapshot)
        case let .completed(confirmation):
            .completed(confirmation)
        case let .completedButUnverified(confirmation):
            .completedButUnverified(confirmation)
        case .cancelled:
            .cancelled
        case .pending:
            .pending
        case let .failed(error):
            .failed(error)
        }
    }
}
