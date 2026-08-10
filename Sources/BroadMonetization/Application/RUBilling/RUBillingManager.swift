/// Single app-facing facade for the complete RU flow. Backend-specific paths,
/// request bodies and authorization remain replaceable wire adapters in the
/// composition factory.
public struct RUBillingManager: Sendable {
    private let services: RUBillingServices

    public init(services: RUBillingServices) {
        self.services = services
    }

    public func startCheckout(
        _ selection: ProductSelection,
        using method: CheckoutMethod,
        remoteConfiguration: RemotePaywallConfiguration,
        details: RUCheckoutDetails
    ) async -> RUCheckoutFlowOutcome {
        await services.checkout.startSelectedProduct(
            selection,
            using: method,
            remoteConfiguration: remoteConfiguration,
            options: CheckoutOptions(ruDetails: details)
        )
    }

    public func applicationDidBecomeActive() async -> RUPaymentReturnOutcome {
        await services.checkout.applicationReturn.applicationDidBecomeActive()
    }

    public func loadSubscriptionStatus()
        async -> RUSubscriptionManagementLoadOutcome {
        await services.checkout.loadSubscriptionStatus()
    }

    public func cancelSubscription(
        id: RUSubscriptionID
    ) async -> RUSubscriptionCancellationOutcome {
        await services.checkout.cancelSubscription(subscriptionID: id)
    }
}
