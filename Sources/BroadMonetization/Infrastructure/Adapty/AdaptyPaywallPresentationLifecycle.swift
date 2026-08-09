import Adapty

public struct AdaptyPaywallPresentationLifecycle: PaywallPresentationLifecycleProtocol {
    private let configuration: AdaptyPlatformConfiguration
    private let identityProvider: any AdaptyIdentityProviderProtocol
    private let context: AdaptyRepositoryContext

    init(
        configuration: AdaptyPlatformConfiguration,
        identityProvider: any AdaptyIdentityProviderProtocol,
        context: AdaptyRepositoryContext
    ) {
        self.configuration = configuration
        self.identityProvider = identityProvider
        self.context = context
    }

    public func presentationDidAppear(
        _ analyticsContext: PaywallAnalyticsContext
    ) async {
        guard let paywall = await context.productRegistry.reservePaywallForShow(
            presentationID: analyticsContext.presentationID,
            reference: analyticsContext.paywallReference
        ) else {
            return
        }

        // Reservation is completed before returning, so a following close can
        // release the registry immediately. SDK logging owns its captured raw
        // value and cannot hold the financial resource registry hostage.
        Task {
            _ = await AdaptySDKActivationGate.shared.perform(
                configuration: configuration,
                identityProvider: identityProvider,
                compositionID: context.sdkCompositionID,
                operation: {
                    try? await Adapty.logShowPaywall(paywall)
                }
            )
        }
    }

    public func presentationDidEnd(
        _ analyticsContext: PaywallAnalyticsContext
    ) async {
        await context.productRegistry.release(
            presentationID: analyticsContext.presentationID,
            reference: analyticsContext.paywallReference
        )
    }
}
