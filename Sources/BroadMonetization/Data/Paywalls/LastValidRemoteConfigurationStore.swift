public actor LastValidRemoteConfigurationStore {
    private var configurations: [PlacementID: RemotePaywallConfiguration] = [:]

    public init() {}

    /// Missing ordinary fields retain their last valid value. Special offer is different:
    /// an absent fresh gate means the optional feature is off and must not be resurrected.
    public func resolve(
        _ parsed: RemotePaywallConfiguration,
        for placementID: PlacementID
    ) -> RemotePaywallConfiguration {
        let previous = configurations[placementID]
        let resolved = RemotePaywallConfiguration(
            ruBillingGateDecision: parsed.ruBillingGateDecision,
            isAutomaticRevenueViewEnabled: parsed.isAutomaticRevenueViewEnabled
                ?? previous?.isAutomaticRevenueViewEnabled,
            accessPolicy: parsed.accessPolicy ?? previous?.accessPolicy,
            closeDelay: parsed.closeDelay ?? previous?.closeDelay,
            uiVariantID: parsed.uiVariantID ?? previous?.uiVariantID,
            specialOffer: parsed.specialOffer,
            authorizesFinancialFeatures: false
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
