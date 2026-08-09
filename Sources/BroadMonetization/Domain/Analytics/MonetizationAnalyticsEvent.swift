import BroadCore

public struct MonetizationAnalyticsFailure: Equatable, Sendable {
    public let kind: AppError.Kind
    public let diagnosticCode: String

    public init(error: AppError) {
        kind = error.kind
        diagnosticCode = error.diagnosticCode
    }
}

public struct PaywallLoadAnalyticsContext: Equatable, Sendable {
    public let attemptID: MonetizationAttemptID
    public let requestedPlacementID: PlacementID
    public let fallbackPlacementID: PlacementID

    public init(
        attemptID: MonetizationAttemptID,
        request: PaywallLoadRequest
    ) {
        self.attemptID = attemptID
        requestedPlacementID = request.placementID
        fallbackPlacementID = request.fallbackPlacementID
    }
}

public struct PaywallAnalyticsContext: Equatable, Sendable {
    public let presentationID: PaywallPresentationID
    public let paywallReference: PaywallReference
    public let variationID: PaywallVariationID?
    public let requestedPlacementID: PlacementID
    public let resolvedPlacementID: PlacementID
    public let fallbackReason: PaywallFallbackReason?
    public let productCount: Int

    public init(paywall: PaywallPayload) {
        presentationID = paywall.presentationID
        paywallReference = paywall.paywallReference
        variationID = paywall.variationID
        requestedPlacementID = paywall.origin.requestedPlacementID
        resolvedPlacementID = paywall.origin.resolvedPlacementID
        fallbackReason = paywall.origin.fallbackReason
        productCount = paywall.products.count
    }
}

public struct PurchaseAnalyticsContext: Codable, Equatable, Sendable {
    public let attemptID: MonetizationAttemptID
    public let paywallPresentationID: PaywallPresentationID
    public let paywallVariationID: PaywallVariationID?
    public let requestedPlacementID: PlacementID
    public let resolvedPlacementID: PlacementID
    public let productPresentationID: ProductPresentationID
    public let productID: ProductID
    public let checkoutMethod: CheckoutMethod

    public init(
        attemptID: MonetizationAttemptID,
        selection: ProductSelection,
        checkoutMethod: CheckoutMethod
    ) {
        self.attemptID = attemptID
        paywallPresentationID = selection.paywallPresentationID
        paywallVariationID = selection.paywallVariationID
        requestedPlacementID = selection.requestedPlacementID
        resolvedPlacementID = selection.resolvedPlacementID
        productPresentationID = selection.product.presentationID
        productID = selection.product.productID
        self.checkoutMethod = checkoutMethod
    }
}

public struct ProductAnalyticsContext: Equatable, Sendable {
    public let presentationID: ProductPresentationID
    public let productID: ProductID

    public init(product: MonetizationProduct) {
        presentationID = product.presentationID
        productID = product.productID
    }
}

public struct RestoreAnalyticsContext: Equatable, Sendable {
    public let attemptID: MonetizationAttemptID

    public init(attemptID: MonetizationAttemptID) {
        self.attemptID = attemptID
    }
}

public struct EntitlementAnalyticsSource: Equatable, Sendable {
    public let source: EntitlementSource
    public let state: EntitlementState
    public let freshness: EntitlementFreshness

    public init(evaluation: EntitlementSourceEvaluation) {
        source = evaluation.source
        state = evaluation.state
        freshness = evaluation.freshness
    }
}

/// Contains only an app-generated correlation ID and typed authority results.
/// It deliberately excludes subject identity, receipts, SDK payloads and errors.
public struct EntitlementAnalyticsContext: Equatable, Sendable {
    public let attemptID: MonetizationAttemptID
    public let state: EntitlementState
    public let freshness: EntitlementFreshness
    public let sources: [EntitlementAnalyticsSource]

    public init(
        attemptID: MonetizationAttemptID,
        snapshot: EntitlementSnapshot
    ) {
        self.attemptID = attemptID
        state = snapshot.state
        freshness = snapshot.freshness
        sources = snapshot.sources.map(EntitlementAnalyticsSource.init)
    }
}

/// Contains only app-generated correlation and catalog metadata. It deliberately
/// excludes email, payment URL, checkout session ID, bearer and user identity.
public struct RUCheckoutAnalyticsContext: Equatable, Sendable {
    public let attemptID: MonetizationAttemptID
    public let productID: RUCatalogProductID
    public let checkoutMethod: CheckoutMethod
    public let paywallPresentationID: PaywallPresentationID?
    public let paywallVariationID: PaywallVariationID?
    public let requestedPlacementID: PlacementID?
    public let resolvedPlacementID: PlacementID?

    public init(
        attemptID: MonetizationAttemptID,
        productID: RUCatalogProductID,
        checkoutMethod: CheckoutMethod,
        paywallPresentationID: PaywallPresentationID? = nil,
        paywallVariationID: PaywallVariationID? = nil,
        requestedPlacementID: PlacementID? = nil,
        resolvedPlacementID: PlacementID? = nil
    ) {
        precondition(
            checkoutMethod == .sbp || checkoutMethod == .card,
            "RU checkout analytics supports only SBP or card"
        )
        let hasCompletePaywallOrigin = paywallPresentationID != nil
            && requestedPlacementID != nil
            && resolvedPlacementID != nil
        let hasNoPaywallOrigin = paywallPresentationID == nil
            && requestedPlacementID == nil
            && resolvedPlacementID == nil
        precondition(
            hasCompletePaywallOrigin || hasNoPaywallOrigin,
            "RU checkout analytics requires a complete paywall origin"
        )
        precondition(
            paywallVariationID == nil || paywallPresentationID != nil,
            "RU checkout variation requires a paywall presentation"
        )
        self.attemptID = attemptID
        self.productID = productID
        self.checkoutMethod = checkoutMethod
        self.paywallPresentationID = paywallPresentationID
        self.paywallVariationID = paywallVariationID
        self.requestedPlacementID = requestedPlacementID
        self.resolvedPlacementID = resolvedPlacementID
    }

    public init(
        attemptID: MonetizationAttemptID,
        selection: ProductSelection,
        productID: RUCatalogProductID,
        checkoutMethod: CheckoutMethod
    ) {
        self.init(
            attemptID: attemptID,
            productID: productID,
            checkoutMethod: checkoutMethod,
            paywallPresentationID: selection.paywallPresentationID,
            paywallVariationID: selection.paywallVariationID,
            requestedPlacementID: selection.requestedPlacementID,
            resolvedPlacementID: selection.resolvedPlacementID
        )
    }
}

public enum PaywallCloseReason: String, Equatable, Sendable {
    case dismissed
    case purchased
    case unavailable
    case navigation
}

public enum MonetizationAnalyticsEvent: Equatable, Sendable {
    case paywallLoadStarted(PaywallLoadAnalyticsContext)
    case paywallLoadSuccess(PaywallLoadAnalyticsContext, paywall: PaywallAnalyticsContext)
    case paywallLoadFailed(PaywallLoadAnalyticsContext, failure: MonetizationAnalyticsFailure)
    case paywallShown(PaywallAnalyticsContext)
    case paywallClosed(PaywallAnalyticsContext, reason: PaywallCloseReason)
    case productSelected(PaywallAnalyticsContext, product: ProductAnalyticsContext)

    case purchaseStarted(PurchaseAnalyticsContext)
    case purchaseSuccess(PurchaseAnalyticsContext)
    case purchaseCompletedButUnverified(PurchaseAnalyticsContext)
    case purchaseCancelled(PurchaseAnalyticsContext)
    case purchasePending(PurchaseAnalyticsContext)
    case purchaseFailed(PurchaseAnalyticsContext, failure: MonetizationAnalyticsFailure)

    case restoreStarted(RestoreAnalyticsContext)
    case restoreSuccess(RestoreAnalyticsContext)
    case restoreNothingFound(RestoreAnalyticsContext)
    case restoreUnavailable(RestoreAnalyticsContext, failure: MonetizationAnalyticsFailure)

    case entitlementResolved(EntitlementAnalyticsContext)

    case ruCheckoutCreated(RUCheckoutAnalyticsContext)
    case ruCheckoutOpenFailed(RUCheckoutAnalyticsContext, failure: MonetizationAnalyticsFailure)
    case ruCheckoutSafariReturned(RUCheckoutAnalyticsContext)
    case ruCheckoutConfirmed(RUCheckoutAnalyticsContext)
    case ruCheckoutTimedOut(RUCheckoutAnalyticsContext)
}
