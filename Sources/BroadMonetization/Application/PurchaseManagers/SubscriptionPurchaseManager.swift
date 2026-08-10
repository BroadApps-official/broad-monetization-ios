/// Small facade for applications that sell premium access only. It has no
/// dependency on token balance, token fulfillment or token UI.
public actor SubscriptionPurchaseManager {
    private let checkout: any CheckoutSelectedProductUseCaseProtocol
    private let restorePurchases: any RestorePurchasesUseCaseProtocol

    public init(
        checkout: any CheckoutSelectedProductUseCaseProtocol,
        restorePurchases: any RestorePurchasesUseCaseProtocol
    ) {
        self.checkout = checkout
        self.restorePurchases = restorePurchases
    }

    public func purchase(
        _ selection: ProductSelection,
        using method: CheckoutMethod,
        remoteConfiguration: RemotePaywallConfiguration,
        options: CheckoutOptions = .standard
    ) async -> CheckoutSelectedProductOutcome {
        await checkout(
            selection,
            using: method,
            remoteConfiguration: remoteConfiguration,
            options: options
        )
    }

    public func restore() async -> RestoreOutcome {
        await restorePurchases()
    }
}
