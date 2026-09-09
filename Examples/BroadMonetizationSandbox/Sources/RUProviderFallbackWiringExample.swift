import BroadCore
import BroadMonetization

/// Compile-only: no SDK activation, HTTP request or real payment.
enum RUProviderFallbackWiringExample {
    static func makeLoader(
        ruFactory: RUBillingCompositionFactory,
        provider: AdaptyPaywallRepository,
        lifecycle: any PaywallPresentationLifecycleProtocol,
        errors: MonetizationFlowErrors
    ) -> any LoadPaywallUseCaseProtocol {
        ruFactory.makePaywallLoader(
            provider: provider,
            presentationLifecycle: lifecycle,
            staleLoadError: errors.stalePaywallLoad
        )
    }
}
