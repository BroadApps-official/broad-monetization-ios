public struct RemoteConfigKeyRegistry: Sendable {
    public static let broadApps = RemoteConfigKeyRegistry(
        ruBillingGate: ["ru_pay", "pay", "russian_payment", "ru_billing"],
        automaticRevenueView: [
            "auto_revenue_view",
            "auto_revnue_view",
            "auto_revinue_view"
        ],
        hardPaywall: ["hardPaywall", "hard_paywall", "isHard", "is_hard", "hard"],
        closeDelay: ["closeDelay", "close_delay", "close_delay_seconds"],
        uiVariant: ["ui_variant", "uiVariant"],
        specialOfferGate: ["special_offer"],
        specialOfferDurationHours: [
            "specialOfferDurationHours",
            "special_offer_duration_hours",
            "couponDurationHours",
            "coupon_duration_hours"
        ],
        specialOfferCooldownHours: [
            "specialOfferCooldownHours",
            "special_offer_cooldown_hours",
            "couponCooldownHours",
            "coupon_cooldown_hours"
        ],
        crossedPrice: [
            "specialOfferCrossedPriceText",
            "special_offer_crossed_price_text",
            "crossedPriceText",
            "crossed_price_text"
        ],
        crossedValue: [
            "specialOfferCrossedPriceValue",
            "special_offer_crossed_price_value",
            "crossedPriceValue",
            "crossed_price_value"
        ],
        priceMultiplier: [
            "specialOfferCrossedPriceMultiplier",
            "special_offer_crossed_price_multiplier",
            "crossedPriceMultiplier",
            "crossed_price_multiplier",
            "old_price_multiplier"
        ],
        specialOfferBadge: ["specialOfferBadge", "special_offer_badge", "offerBadge", "offer_badge"],
        specialOfferPeriodText: [
            "specialOfferPeriodText",
            "special_offer_period_text",
            "periodText",
            "period_text"
        ]
    )

    public let ruBillingGate: [String]
    public let automaticRevenueView: [String]
    public let hardPaywall: [String]
    public let closeDelay: [String]
    public let uiVariant: [String]
    public let specialOfferGate: [String]
    public let specialOfferDurationHours: [String]
    public let specialOfferCooldownHours: [String]
    public let crossedPrice: [String]
    public let crossedValue: [String]
    public let priceMultiplier: [String]
    public let specialOfferBadge: [String]
    public let specialOfferPeriodText: [String]

    public init(
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
        let groups = [
            ruBillingGate,
            automaticRevenueView,
            hardPaywall,
            closeDelay,
            uiVariant,
            specialOfferGate,
            specialOfferDurationHours,
            specialOfferCooldownHours,
            crossedPrice,
            crossedValue,
            priceMultiplier,
            specialOfferBadge,
            specialOfferPeriodText
        ]
        precondition(
            groups.allSatisfy { !$0.isEmpty && Set($0).count == $0.count },
            "Every remote-config field requires non-empty, unique aliases"
        )

        self.ruBillingGate = ruBillingGate
        self.automaticRevenueView = automaticRevenueView
        self.hardPaywall = hardPaywall
        self.closeDelay = closeDelay
        self.uiVariant = uiVariant
        self.specialOfferGate = specialOfferGate
        self.specialOfferDurationHours = specialOfferDurationHours
        self.specialOfferCooldownHours = specialOfferCooldownHours
        self.crossedPrice = crossedPrice
        self.crossedValue = crossedValue
        self.priceMultiplier = priceMultiplier
        self.specialOfferBadge = specialOfferBadge
        self.specialOfferPeriodText = specialOfferPeriodText
    }
}
