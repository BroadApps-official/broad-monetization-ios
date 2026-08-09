public struct BroadMonetizationServices: Sendable {
    public let activate: any ActivateMonetizationUseCaseProtocol
    public let loadPaywall: any LoadPaywallUseCaseProtocol
    public let selectProduct: any SelectProductUseCaseProtocol
    public let purchaseProduct: any PurchaseSelectedProductUseCaseProtocol
    public let checkoutProduct: any CheckoutSelectedProductUseCaseProtocol
    public let restorePurchases: any RestorePurchasesUseCaseProtocol
    public let analytics: any MonetizationAnalyticsProtocol
    public let paywallPresentationLifecycle: any PaywallPresentationLifecycleProtocol
    public let trackPaywallEvent: any TrackPaywallEventUseCaseProtocol
    public let operationGate: MonetizationOperationGate
    public let pendingApplePurchase: PendingApplePurchaseCoordinator?

    public init(
        activate: any ActivateMonetizationUseCaseProtocol,
        loadPaywall: any LoadPaywallUseCaseProtocol,
        selectProduct: any SelectProductUseCaseProtocol,
        purchaseProduct: any PurchaseSelectedProductUseCaseProtocol,
        restorePurchases: any RestorePurchasesUseCaseProtocol,
        analytics: any MonetizationAnalyticsProtocol,
        paywallPresentationLifecycle: any PaywallPresentationLifecycleProtocol,
        checkoutProduct: (any CheckoutSelectedProductUseCaseProtocol)? = nil,
        operationGate: MonetizationOperationGate? = nil,
        pendingApplePurchase: PendingApplePurchaseCoordinator? = nil
    ) {
        let purchaseGate = (purchaseProduct as? any MonetizationOperationGateProviding)?
            .monetizationOperationGate
        let restoreGate = (restorePurchases as? any MonetizationOperationGateProviding)?
            .monetizationOperationGate
        precondition(
            purchaseGate != nil,
            "Purchase use case must expose its MonetizationOperationGate"
        )
        precondition(
            restoreGate != nil,
            "Restore use case must expose its MonetizationOperationGate"
        )
        let resolvedGate = operationGate ?? purchaseGate ?? restoreGate
            ?? MonetizationOperationGate()

        precondition(
            purchaseGate == nil || purchaseGate === resolvedGate,
            "Purchase use case must use the composition operation gate"
        )
        precondition(
            restoreGate == nil || restoreGate === resolvedGate,
            "Restore use case must use the composition operation gate"
        )

        self.activate = activate
        self.loadPaywall = loadPaywall
        self.selectProduct = selectProduct
        self.purchaseProduct = purchaseProduct
        self.checkoutProduct = checkoutProduct ?? CheckoutSelectedProductUseCase(
            applePurchase: purchaseProduct
        )
        self.restorePurchases = restorePurchases
        let deliveryAnalytics = NonBlockingMonetizationAnalytics.wrapping(analytics)
        self.analytics = deliveryAnalytics
        self.paywallPresentationLifecycle = paywallPresentationLifecycle
        trackPaywallEvent = TrackPaywallEventUseCase(
            analytics: deliveryAnalytics,
            presentationLifecycle: paywallPresentationLifecycle
        )
        self.operationGate = resolvedGate
        self.pendingApplePurchase = pendingApplePurchase
    }
}
