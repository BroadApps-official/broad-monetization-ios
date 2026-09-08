public extension AdaptyMonetizationFactory {
    /// Preserves the pre-1.4 initializer, including typed function references.
    init(
        configuration: AdaptyPlatformConfiguration,
        placementRegistry: AdaptyPlacementRegistry,
        messages: AdaptyMonetizationMessages,
        remoteConfigurationParser: RemotePaywallConfigurationParser = .init(),
        remoteConfigurationStore: LastValidRemoteConfigurationStore = .init(),
        context: AdaptyRepositoryContext = .init()
    ) {
        self.init(
            configuration: configuration,
            placementRegistry: placementRegistry,
            messages: messages,
            remoteConfigurationParser: remoteConfigurationParser,
            remoteConfigurationStore: remoteConfigurationStore,
            context: context,
            ruBillingExperiments: nil
        )
    }

    /// Preserves the pre-1.4 initializer, including typed function references.
    init(
        configuration: AdaptyPlatformConfiguration,
        identityProvider: any AdaptyIdentityProviderProtocol,
        placementRegistry: AdaptyPlacementRegistry,
        messages: AdaptyMonetizationMessages,
        remoteConfigurationParser: RemotePaywallConfigurationParser = .init(),
        remoteConfigurationStore: LastValidRemoteConfigurationStore = .init(),
        context: AdaptyRepositoryContext = .init()
    ) {
        self.init(
            configuration: configuration,
            identityProvider: identityProvider,
            placementRegistry: placementRegistry,
            messages: messages,
            remoteConfigurationParser: remoteConfigurationParser,
            remoteConfigurationStore: remoteConfigurationStore,
            context: context,
            ruBillingExperiments: nil
        )
    }
}
