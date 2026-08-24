import Foundation

public enum PaywallAccessPolicy: String, Codable, Equatable, Sendable {
    case soft
    case hard
}

public enum RemoteRUBillingGateDecision: String, Codable, Equatable, Sendable {
    case absent
    case enabled
    case disabled
    case invalid

    var booleanValue: Bool? {
        switch self {
        case .enabled: true
        case .disabled: false
        case .absent, .invalid: nil
        }
    }
}

/// Parsed domain configuration. `nil` fields mean "not supplied" and allow the
/// repository to retain a previous valid value instead of resetting it silently.
public struct RemotePaywallConfiguration: Codable, Equatable, Sendable {
    public static let empty = RemotePaywallConfiguration()

    public let isRUBillingEnabled: Bool?
    public let ruBillingGateDecision: RemoteRUBillingGateDecision
    public let isAutomaticRevenueViewEnabled: Bool?
    public let accessPolicy: PaywallAccessPolicy?
    public let closeDelay: TimeInterval?
    public let uiVariantID: PaywallUIVariantID?
    public let specialOffer: SpecialOfferRemoteConfiguration?
    private(set) var authorizesRUBillingPresentation: Bool

    public init(
        isRUBillingEnabled: Bool? = nil,
        isAutomaticRevenueViewEnabled: Bool? = nil,
        accessPolicy: PaywallAccessPolicy? = nil,
        closeDelay: TimeInterval? = nil,
        uiVariantID: PaywallUIVariantID? = nil,
        specialOffer: SpecialOfferRemoteConfiguration? = nil
    ) {
        if let closeDelay {
            precondition(
                closeDelay.isFinite && closeDelay >= 0,
                "Paywall close delay must be finite and non-negative"
            )
        }

        self.isRUBillingEnabled = isRUBillingEnabled
        ruBillingGateDecision = switch isRUBillingEnabled {
        case .some(true): .enabled
        case .some(false): .disabled
        case .none: .absent
        }
        self.isAutomaticRevenueViewEnabled = isAutomaticRevenueViewEnabled
        self.accessPolicy = accessPolicy
        self.closeDelay = closeDelay
        self.uiVariantID = uiVariantID
        self.specialOffer = specialOffer
        authorizesRUBillingPresentation = false
    }

    init(
        ruBillingGateDecision: RemoteRUBillingGateDecision,
        isAutomaticRevenueViewEnabled: Bool?,
        accessPolicy: PaywallAccessPolicy?,
        closeDelay: TimeInterval?,
        uiVariantID: PaywallUIVariantID?,
        specialOffer: SpecialOfferRemoteConfiguration?,
        authorizesRUBillingPresentation: Bool
    ) {
        if let closeDelay {
            precondition(
                closeDelay.isFinite && closeDelay >= 0,
                "Paywall close delay must be finite and non-negative"
            )
        }
        isRUBillingEnabled = ruBillingGateDecision.booleanValue
        self.ruBillingGateDecision = ruBillingGateDecision
        self.isAutomaticRevenueViewEnabled = isAutomaticRevenueViewEnabled
        self.accessPolicy = accessPolicy
        self.closeDelay = closeDelay
        self.uiVariantID = uiVariantID
        self.specialOffer = specialOffer
        self.authorizesRUBillingPresentation = authorizesRUBillingPresentation
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let closeDelay = try Self.decodeCloseDelay(from: container)
        let gateDecision = try Self.decodeGateDecision(from: container)
        try self.init(
            ruBillingGateDecision: gateDecision,
            isAutomaticRevenueViewEnabled: container.decodeIfPresent(
                Bool.self,
                forKey: .isAutomaticRevenueViewEnabled
            ),
            accessPolicy: container.decodeIfPresent(
                PaywallAccessPolicy.self,
                forKey: .accessPolicy
            ),
            closeDelay: closeDelay,
            uiVariantID: container.decodeIfPresent(
                PaywallUIVariantID.self,
                forKey: .uiVariantID
            ),
            specialOffer: container.decodeIfPresent(
                SpecialOfferRemoteConfiguration.self,
                forKey: .specialOffer
            ),
            authorizesRUBillingPresentation: false
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(isRUBillingEnabled, forKey: .isRUBillingEnabled)
        try container.encode(ruBillingGateDecision, forKey: .ruBillingGateDecision)
        try container.encodeIfPresent(
            isAutomaticRevenueViewEnabled,
            forKey: .isAutomaticRevenueViewEnabled
        )
        try container.encodeIfPresent(accessPolicy, forKey: .accessPolicy)
        try container.encodeIfPresent(closeDelay, forKey: .closeDelay)
        try container.encodeIfPresent(uiVariantID, forKey: .uiVariantID)
        try container.encodeIfPresent(specialOffer, forKey: .specialOffer)
    }

    func qualified(
        by provenance: PaywallRemoteConfigurationProvenance
    ) -> RemotePaywallConfiguration {
        RemotePaywallConfiguration(
            ruBillingGateDecision: ruBillingGateDecision,
            isAutomaticRevenueViewEnabled: isAutomaticRevenueViewEnabled,
            accessPolicy: accessPolicy,
            closeDelay: closeDelay,
            uiVariantID: uiVariantID,
            specialOffer: provenance.authorizesSpecialOfferPresentation
                ? specialOffer
                : nil,
            authorizesRUBillingPresentation: provenance
                .authorizesRUBillingPresentation
        )
    }

    private enum CodingKeys: String, CodingKey {
        case isRUBillingEnabled
        case ruBillingGateDecision
        case isAutomaticRevenueViewEnabled
        case accessPolicy
        case closeDelay
        case uiVariantID
        case specialOffer
    }

    private static func decodeCloseDelay(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> TimeInterval? {
        let closeDelay = try container.decodeIfPresent(
            TimeInterval.self,
            forKey: .closeDelay
        )
        guard closeDelay?.isFinite != false,
              closeDelay.map({ $0 >= 0 }) != false
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .closeDelay,
                in: container,
                debugDescription: "Remote close delay must be finite and non-negative"
            )
        }
        return closeDelay
    }

    private static func decodeGateDecision(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> RemoteRUBillingGateDecision {
        let decodedBoolean = try container.decodeIfPresent(
            Bool.self,
            forKey: .isRUBillingEnabled
        )
        let decodedDecision = try container.decodeIfPresent(
            RemoteRUBillingGateDecision.self,
            forKey: .ruBillingGateDecision
        )
        let decision = decodedDecision ?? decision(for: decodedBoolean)
        guard decision.booleanValue == decodedBoolean else {
            throw DecodingError.dataCorruptedError(
                forKey: .ruBillingGateDecision,
                in: container,
                debugDescription: "RU billing gate decision is inconsistent"
            )
        }
        return decision
    }

    private static func decision(
        for value: Bool?
    ) -> RemoteRUBillingGateDecision {
        switch value {
        case .some(true): .enabled
        case .some(false): .disabled
        case .none: .absent
        }
    }
}
