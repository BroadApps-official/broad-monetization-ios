public extension RemoteConfigKeyRegistry {
    /// Preserves the pre-1.4 initializer, including typed function references.
    init(
        ruBillingGate: [String],
        automaticRevenueView: [String] = ["auto_revenue_view"],
        hardPaywall: [String],
        closeDelay: [String],
        uiVariant: [String],
        specialOfferGate: [String],
        specialOfferDurationHours: [String],
        specialOfferCooldownHours: [String],
        crossedPrice: [String],
        crossedValue: [String],
        priceMultiplier: [String],
        specialOfferBadge: [String],
        specialOfferPeriodText: [String]
    ) {
        self.init(
            ruBillingGate: ruBillingGate,
            automaticRevenueView: automaticRevenueView,
            hardPaywall: hardPaywall,
            closeDelay: closeDelay,
            uiVariant: uiVariant,
            specialOfferGate: specialOfferGate,
            specialOfferDurationHours: specialOfferDurationHours,
            specialOfferCooldownHours: specialOfferCooldownHours,
            crossedPrice: crossedPrice,
            crossedValue: crossedValue,
            priceMultiplier: priceMultiplier,
            specialOfferBadge: specialOfferBadge,
            specialOfferPeriodText: specialOfferPeriodText,
            ruExperimentCode: "experiment_code",
            ruSegmentCode: "segment_code"
        )
    }
}
