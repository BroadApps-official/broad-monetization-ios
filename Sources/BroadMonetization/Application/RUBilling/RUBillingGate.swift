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
        allows(
            remoteConfiguration: remoteConfiguration,
            storefront: nil
        )
    }

    public func allows(
        remoteConfiguration: RemotePaywallConfiguration,
        storefront: Storefront?
    ) -> Bool {
        availabilityReason(
            remoteConfiguration: remoteConfiguration,
            storefront: storefront
        ).allowsRUBilling
    }

    public func availabilityReason(
        remoteConfiguration: RemotePaywallConfiguration
    ) -> RUBillingAvailabilityReason {
        availabilityReason(
            remoteConfiguration: remoteConfiguration,
            storefront: nil
        )
    }

    public func availabilityReason(
        remoteConfiguration: RemotePaywallConfiguration,
        storefront: Storefront?
    ) -> RUBillingAvailabilityReason {
        guard isFeatureEnabled else {
            return .hostDisabled
        }

        switch debugOverrideStore.currentMode {
        case .forceEnabled:
            return hasRussianRegionalSignal(storefront: storefront)
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

        return hasRussianRegionalSignal(storefront: storefront)
            ? .available
            : .deviceContextNotRussian
    }
}

private extension RUBillingGate {
    func hasRussianRegionalSignal(storefront: Storefront?) -> Bool {
        storefront?.isRussian == true
            || deviceContextProvider.currentContext().isRussian
    }
}
