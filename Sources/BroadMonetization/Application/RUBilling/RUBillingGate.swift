public enum RUBillingRemoteGateFallbackPolicy: Equatable, Sendable {
    case disabled
    case enabled
}

public struct RUBillingGate: Sendable {
    private let isFeatureEnabled: Bool
    private let remoteFallback: RUBillingRemoteGateFallbackPolicy

    public init(
        isFeatureEnabled: Bool,
        remoteFallback: RUBillingRemoteGateFallbackPolicy = .disabled
    ) {
        self.isFeatureEnabled = isFeatureEnabled
        self.remoteFallback = remoteFallback
    }

    public func allows(
        remoteConfiguration: RemotePaywallConfiguration,
        storefront: Storefront
    ) -> Bool {
        mayBeEligible(remoteConfiguration: remoteConfiguration) && storefront.isRussian
    }

    public func mayBeEligible(
        remoteConfiguration: RemotePaywallConfiguration
    ) -> Bool {
        guard isFeatureEnabled else {
            return false
        }
        switch remoteConfiguration.ruBillingGateDecision {
        case .disabled, .invalid:
            // A kill switch is safe to honor even from provider/local cache.
            return false
        case .enabled:
            // Cached or otherwise unqualified positive values never authorize
            // a financial feature, even when a host fallback exists.
            return remoteConfiguration.authorizesFinancialFeatures
        case .absent:
            // Only an absent remote decision may defer to explicit host policy.
            return remoteFallback == .enabled
        }
    }
}
