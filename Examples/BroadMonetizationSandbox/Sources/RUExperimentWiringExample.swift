import BroadMonetization

/// Compile-only examples for existing host composition objects. The sandbox
/// does not call these functions or activate an SDK/backend connection.
enum RUExperimentWiringExample {
    static func legacy(
        configuration: AdaptyPlatformConfiguration,
        identity: any AdaptyIdentityProviderProtocol,
        placements: AdaptyPlacementRegistry,
        messages: AdaptyMonetizationMessages,
        context: AdaptyRepositoryContext
    ) -> AdaptyMonetizationFactory {
        AdaptyMonetizationFactory(
            configuration: configuration, identityProvider: identity,
            placementRegistry: placements, messages: messages, context: context
        )
    }

    static func withRUExperiments(
        configuration: AdaptyPlatformConfiguration,
        identity: any AdaptyIdentityProviderProtocol,
        placements: AdaptyPlacementRegistry,
        messages: AdaptyMonetizationMessages,
        context: AdaptyRepositoryContext,
        ruFactory: RUBillingCompositionFactory
    ) -> AdaptyMonetizationFactory {
        let experiments = ruFactory.makeExperimentTracker(configuration: .broadApps)
        return AdaptyMonetizationFactory(
            configuration: configuration, identityProvider: identity,
            placementRegistry: placements, messages: messages, context: context,
            ruBillingExperiments: experiments
        )
    }
}
