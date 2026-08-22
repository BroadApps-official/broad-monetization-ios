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
            // This only authorizes presenting a configured checkout method.
            // The backend and entitlement engine remain the authorities for
            // payment status and premium access.
            return remoteConfiguration.authorizesRUBillingPresentation
        case .absent:
            // RU billing is never enabled without an explicit `ru_pay = true`.
            return false
        }
    }
}
