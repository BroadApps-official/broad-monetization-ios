import Foundation

public extension RemotePaywallConfiguration {
    /// Preserves the pre-1.4 initializer, including typed function references.
    init(
        isRUBillingEnabled: Bool? = nil,
        isAutomaticRevenueViewEnabled: Bool? = nil,
        accessPolicy: PaywallAccessPolicy? = nil,
        closeDelay: TimeInterval? = nil,
        uiVariantID: PaywallUIVariantID? = nil,
        specialOffer: SpecialOfferRemoteConfiguration? = nil
    ) {
        self.init(
            isRUBillingEnabled: isRUBillingEnabled,
            isAutomaticRevenueViewEnabled: isAutomaticRevenueViewEnabled,
            accessPolicy: accessPolicy,
            closeDelay: closeDelay,
            uiVariantID: uiVariantID,
            specialOffer: specialOffer,
            ruExperiment: nil
        )
    }
}
