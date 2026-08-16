public struct RUBillingGate: Sendable {
    private let isFeatureEnabled: Bool
    private let deviceContextProvider: any RUBillingDeviceContextProviderProtocol

    public init(
        isFeatureEnabled: Bool,
        deviceContextProvider: any RUBillingDeviceContextProviderProtocol =
            SystemRUBillingDeviceContextProvider()
    ) {
        self.isFeatureEnabled = isFeatureEnabled
        self.deviceContextProvider = deviceContextProvider
    }

    public func allows(
        remoteConfiguration: RemotePaywallConfiguration
    ) -> Bool {
        mayBeEligible(remoteConfiguration: remoteConfiguration)
            && deviceContextProvider.currentContext().isRussian
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
            // a financial feature.
            return remoteConfiguration.authorizesFinancialFeatures
        case .absent:
            // RU billing is never enabled without an explicit `ru_pay = true`.
            return false
        }
    }
}
