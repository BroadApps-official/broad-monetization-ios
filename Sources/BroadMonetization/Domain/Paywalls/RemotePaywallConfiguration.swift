import Foundation

public enum PaywallAccessPolicy: String, Codable, Equatable, Sendable {
    case soft
    case hard
}

/// Parsed domain configuration. `nil` fields mean "not supplied" and allow the
/// repository to retain a previous valid value instead of resetting it silently.
public struct RemotePaywallConfiguration: Codable, Equatable, Sendable {
    public static let empty = RemotePaywallConfiguration()

    public let isAutomaticRevenueViewEnabled: Bool?
    public let accessPolicy: PaywallAccessPolicy?
    public let closeDelay: TimeInterval?
    public let uiVariantID: PaywallUIVariantID?
    public let specialOffer: SpecialOfferRemoteConfiguration?
    public let providerConfigurations: [String: ProviderRemoteConfiguration]
    public private(set) var authorizesProviderFeatures: Bool
    public var authorizesProviderFallback = false

    public init(
        isAutomaticRevenueViewEnabled: Bool? = nil,
        accessPolicy: PaywallAccessPolicy? = nil,
        closeDelay: TimeInterval? = nil,
        uiVariantID: PaywallUIVariantID? = nil,
        specialOffer: SpecialOfferRemoteConfiguration? = nil,
        providerConfigurations: [String: ProviderRemoteConfiguration] = [:]
    ) {
        if let closeDelay {
            precondition(
                closeDelay.isFinite && closeDelay >= 0,
                "Paywall close delay must be finite and non-negative"
            )
        }

        self.isAutomaticRevenueViewEnabled = isAutomaticRevenueViewEnabled
        self.accessPolicy = accessPolicy
        self.closeDelay = closeDelay
        self.uiVariantID = uiVariantID
        self.specialOffer = specialOffer
        self.providerConfigurations = providerConfigurations
        authorizesProviderFeatures = false
    }

    init(
        isAutomaticRevenueViewEnabled: Bool?,
        accessPolicy: PaywallAccessPolicy?,
        closeDelay: TimeInterval?,
        uiVariantID: PaywallUIVariantID?,
        specialOffer: SpecialOfferRemoteConfiguration?,
        authorizesProviderFeatures: Bool,
        providerConfigurations: [String: ProviderRemoteConfiguration] = [:]
    ) {
        if let closeDelay {
            precondition(
                closeDelay.isFinite && closeDelay >= 0,
                "Paywall close delay must be finite and non-negative"
            )
        }
        self.isAutomaticRevenueViewEnabled = isAutomaticRevenueViewEnabled
        self.accessPolicy = accessPolicy
        self.closeDelay = closeDelay
        self.uiVariantID = uiVariantID
        self.specialOffer = specialOffer
        self.authorizesProviderFeatures = authorizesProviderFeatures
        self.providerConfigurations = providerConfigurations
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let closeDelay = try Self.decodeCloseDelay(from: container)
        try self.init(
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
            authorizesProviderFeatures: false,
            // Experiment metadata belongs to this live response. A persisted
            // payload cannot revive an old reporting assignment.
            providerConfigurations: [:]
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(
            isAutomaticRevenueViewEnabled,
            forKey: .isAutomaticRevenueViewEnabled
        )
        try container.encodeIfPresent(accessPolicy, forKey: .accessPolicy)
        try container.encodeIfPresent(closeDelay, forKey: .closeDelay)
        try container.encodeIfPresent(uiVariantID, forKey: .uiVariantID)
        try container.encodeIfPresent(specialOffer, forKey: .specialOffer)
    }

    public func qualified(
        by provenance: PaywallRemoteConfigurationProvenance
    ) -> RemotePaywallConfiguration {
        var qualified = RemotePaywallConfiguration(
            isAutomaticRevenueViewEnabled: isAutomaticRevenueViewEnabled,
            accessPolicy: accessPolicy,
            closeDelay: closeDelay,
            uiVariantID: uiVariantID,
            specialOffer: provenance.authorizesSpecialOfferPresentation
                ? specialOffer
                : nil,
            authorizesProviderFeatures: provenance
                .authorizesProviderFeatures,
            providerConfigurations: providerConfigurations.mapValues { value in
                ProviderRemoteConfiguration(
                    decisionData: value.decisionData,
                    liveMetadata: provenance.authorizesProviderFeatures ? value.liveMetadata : nil
                )
            }
        )
        qualified.authorizesProviderFallback = authorizesProviderFallback
            && provenance != .platformCache
        return qualified
    }

    private enum CodingKeys: String, CodingKey {
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
}
