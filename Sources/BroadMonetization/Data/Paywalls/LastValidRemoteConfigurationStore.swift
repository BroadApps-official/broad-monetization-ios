public actor LastValidRemoteConfigurationStore {
    private var configurations: [PlacementID: RemotePaywallConfiguration] = [:]

    public init() {}

    /// Missing ordinary UI fields retain their last valid value. provider extensions and
    /// `special_offer` are different: only the current provider payload may
    /// enable them, so an absent, malformed, or false value must never be
    /// resurrected from a previous response.
    public func resolve(
        _ parsed: RemotePaywallConfiguration,
        for placementID: PlacementID
    ) -> RemotePaywallConfiguration {
        let previous = configurations[placementID]
        let resolved = RemotePaywallConfiguration(
            isAutomaticRevenueViewEnabled: parsed.isAutomaticRevenueViewEnabled
                ?? previous?.isAutomaticRevenueViewEnabled,
            accessPolicy: parsed.accessPolicy ?? previous?.accessPolicy,
            closeDelay: parsed.closeDelay ?? previous?.closeDelay,
            uiVariantID: parsed.uiVariantID ?? previous?.uiVariantID,
            specialOffer: parsed.specialOffer,
            providerConfigurations: parsed.providerConfigurations
        )
        configurations[placementID] = resolved
        return resolved
    }

    public func reset(
        placementID: PlacementID
    ) {
        configurations.removeValue(forKey: placementID)
    }

    public func resetAll() {
        configurations.removeAll()
    }
}
