import Adapty

public struct AdaptyPaywallPresentationLifecycle: PaywallPresentationLifecycleProtocol {
    private let configuration: AdaptyPlatformConfiguration
    private let identityProvider: any AdaptyIdentityProviderProtocol
    private let context: AdaptyRepositoryContext
    private let placementRegistry: AdaptyPlacementRegistry?
    private let ruBillingExperiments: RUBillingExperimentTracker?

    init(
        configuration: AdaptyPlatformConfiguration,
        identityProvider: any AdaptyIdentityProviderProtocol,
        context: AdaptyRepositoryContext,
        placementRegistry: AdaptyPlacementRegistry? = nil,
        ruBillingExperiments: RUBillingExperimentTracker? = nil
    ) {
        self.configuration = configuration
        self.identityProvider = identityProvider
        self.context = context
        self.placementRegistry = placementRegistry
        self.ruBillingExperiments = ruBillingExperiments
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

        // Register the attempt before returning, so a fast close cannot race
        // its reservation. No network request delays the presentation lifecycle.
        let report = await ruBillingExperiments?.beginTracking(
            analyticsContext,
            placement: placementRegistry?.adaptyPlacement(
                for: analyticsContext.resolvedPlacementID
            )?.rawValue ?? analyticsContext.resolvedPlacementID.rawValue
        )

        // Reservation is completed before returning, so a following close can
        // release the registry immediately. SDK logging owns its captured raw
        // value and cannot hold the financial resource registry hostage.
        Task {
            if let report, await report.value != .useAdapty {
                // RU failures remain in the RU branch. Falling through would
                // send a view to a counter that cannot observe this purchase.
                return
            }
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
        await ruBillingExperiments?.presentationDidEnd(analyticsContext.presentationID)
    }
}
