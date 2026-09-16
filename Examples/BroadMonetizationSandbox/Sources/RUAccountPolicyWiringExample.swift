import BroadMonetization

/// Compile-only example. The gallery never performs checkout or backend reads.
enum RUAccountPolicyWiringExample {
    static let endpoints = RUBillingEndpointConfiguration(
        catalog: .init(rawValue: "/v1/products"),
        checkout: .init(rawValue: "/v1/billing/cloudpayments/checkout"),
        entitlementStatus: .init(rawValue: "/v1/policy/effective"),
        cancellation: .init(rawValue: "/v1/billing/cloudpayments/cancel")
    )

    static func factory(
        configuration: RUBillingCompositionConfiguration,
        dependencies: RUBillingCompositionDependencies,
        cancellation: RUCancellationWireAdapters
    ) -> RUBillingCompositionFactory {
        precondition(configuration.http.endpoints.paymentStatus == nil)
        let standard = RUBillingWireAdapters.broadAppsAccountPolicy
        return RUBillingCompositionFactory(
            configuration: configuration, dependencies: dependencies,
            wire: .init(
                catalog: standard.catalog,
                checkout: standard.checkout,
                paymentStatus: standard.paymentStatus,
                cancellation: cancellation,
                entitlement: standard.entitlement
            )
        )
    }

    static func startToken(
        services: RUBillingServices, selection: ProductSelection,
        method: CheckoutMethod, remote: RemotePaywallConfiguration, options: CheckoutOptions
    ) async -> RUCheckoutFlowOutcome {
        await services.checkout.startSelectedToken(
            selection, using: method, remoteConfiguration: remote, options: options
        )
    }

    static func paymentPageDismissed(services: RUBillingServices) async -> RUPaymentReturnOutcome {
        await services.checkout.applicationReturn.applicationDidBecomeActive()
    }

    /// Present explicit confirmation before calling this route. The injected
    /// repository must make the checkout terminal on the backend.
    static func abandonPayment(
        services: RUBillingServices
    ) async -> RUPendingCheckoutTerminationOutcome {
        await services.checkout.pendingCheckoutTermination
            .terminatePendingCheckout()
    }
}

/// A compile-only bridge around an existing subject-bound API client.
struct AppCheckoutTerminationClient: RUCheckoutTerminationClientProtocol {
    let terminate: @Sendable (
        RUPendingCheckoutTerminationRequest
    ) async -> RUPendingCheckoutTerminationResult

    func terminatePendingCheckout(
        _ request: RUPendingCheckoutTerminationRequest
    ) async -> RUPendingCheckoutTerminationResult {
        await terminate(request)
    }
}
