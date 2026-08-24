public struct RUBillingGate: Sendable {
    private let isFeatureEnabled: Bool
    private let deviceContextProvider: any RUBillingDeviceContextProviderProtocol
    private let debugOverrideStore: RUBillingDebugOverrideStore

    public init(
        isFeatureEnabled: Bool,
        deviceContextProvider: any RUBillingDeviceContextProviderProtocol =
            SystemRUBillingDeviceContextProvider(),
        debugOverrideStore: RUBillingDebugOverrideStore = RUBillingDebugOverrideStore()
    ) {
        self.isFeatureEnabled = isFeatureEnabled
        self.deviceContextProvider = deviceContextProvider
        self.debugOverrideStore = debugOverrideStore
    }

    public func allows(
        remoteConfiguration: RemotePaywallConfiguration
    ) -> Bool {
        availabilityReason(remoteConfiguration: remoteConfiguration).allowsRUBilling
    }

    public func availabilityReason(
        remoteConfiguration: RemotePaywallConfiguration
    ) -> RUBillingAvailabilityReason {
        guard isFeatureEnabled else {
            return .hostDisabled
        }

        switch debugOverrideStore.currentMode {
        case .forceEnabled:
            return deviceContextProvider.currentContext().isRussian
                ? .debugForcedEnabled
                : .deviceContextNotRussian
        case .forceDisabled:
            return .debugForcedDisabled
        case .followAdapty:
            break
        }

        switch remoteConfiguration.ruBillingGateDecision {
        case .disabled:
            return .remoteFlagDisabled
        case .invalid:
            return .remoteFlagInvalid
        case .enabled:
            // This only authorizes presenting a configured checkout method.
            // The backend and entitlement engine remain the authorities for
            // payment status and premium access.
            guard remoteConfiguration.authorizesRUBillingPresentation else {
                return .unqualifiedRemoteConfiguration
            }
        case .absent:
            // RU billing is never enabled without an explicit `ru_pay = true`.
            return .remoteFlagAbsent
        }

        return deviceContextProvider.currentContext().isRussian
            ? .available
            : .deviceContextNotRussian
    }
}
