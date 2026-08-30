public struct AdaptyMonetizationFactory: Sendable {
    public let context: AdaptyRepositoryContext

    private let configuration: AdaptyPlatformConfiguration
    private let identityProvider: any AdaptyIdentityProviderProtocol
    private let placementRegistry: AdaptyPlacementRegistry
    private let messages: AdaptyMonetizationMessages
    private let remoteConfigurationParser: RemotePaywallConfigurationParser
    private let remoteConfigurationStore: LastValidRemoteConfigurationStore

    /// Basic anonymous Adapty composition. The host supplies the SDK
    /// configuration, placement mapping and localized messages; no custom
    /// identity adapter is needed.
    public init(
        configuration: AdaptyPlatformConfiguration,
        placementRegistry: AdaptyPlacementRegistry,
        messages: AdaptyMonetizationMessages,
        remoteConfigurationParser: RemotePaywallConfigurationParser = .init(),
        remoteConfigurationStore: LastValidRemoteConfigurationStore = .init(),
        context: AdaptyRepositoryContext = .init()
    ) {
        precondition(
            configuration.subject == .anonymous,
            "Basic Adapty composition supports only the anonymous subject"
        )
        self.init(
            configuration: configuration,
            identityProvider: AdaptyAnonymousIdentityProvider(),
            placementRegistry: placementRegistry,
            messages: messages,
            remoteConfigurationParser: remoteConfigurationParser,
            remoteConfigurationStore: remoteConfigurationStore,
            context: context
        )
    }

    /// Advanced composition for a host-owned signed-in Adapty identity.
    public init(
        configuration: AdaptyPlatformConfiguration,
        identityProvider: any AdaptyIdentityProviderProtocol,
        placementRegistry: AdaptyPlacementRegistry,
        messages: AdaptyMonetizationMessages,
        remoteConfigurationParser: RemotePaywallConfigurationParser = .init(),
        remoteConfigurationStore: LastValidRemoteConfigurationStore = .init(),
        context: AdaptyRepositoryContext = .init()
    ) {
        self.configuration = configuration
        self.identityProvider = identityProvider
        self.placementRegistry = placementRegistry
        self.messages = messages
        self.remoteConfigurationParser = remoteConfigurationParser
        self.remoteConfigurationStore = remoteConfigurationStore
        self.context = context
    }

    public var paywallPresentationLifecycle: AdaptyPaywallPresentationLifecycle {
        AdaptyPaywallPresentationLifecycle(
            configuration: configuration,
            identityProvider: identityProvider,
            context: context
        )
    }

    public func makeServices(
        entitlementRepository: any EntitlementRepositoryProtocol,
        analytics: any MonetizationAnalyticsProtocol,
        paywallCache: (any PaywallCacheProtocol)? = nil,
        errors: MonetizationFlowErrors,
        pendingApplePurchaseStore: any PendingApplePurchaseStoreProtocol,
        pendingAppleTransactionRecovery: any PendingAppleTransactionRecoveryProtocol,
        operationGate: MonetizationOperationGate
    ) -> BroadMonetizationServices {
        precondition(
            !configuration.observerMode,
            "Standard Adapty services cannot purchase in observer mode; inject a host StoreKit purchase composition instead"
        )
        let deliveryAnalytics = NonBlockingMonetizationAnalytics.wrapping(analytics)
        let pendingStore = pendingApplePurchaseStore
        let presentationLifecycle = paywallPresentationLifecycle
        let paywallRepository = makePaywallRepository()
        let inputs = AdaptyServiceInputs(
            entitlementRepository: entitlementRepository,
            deliveryAnalytics: deliveryAnalytics,
            paywallCache: paywallCache,
            errors: errors,
            pendingStore: pendingStore,
            transactionRecovery: pendingAppleTransactionRecovery,
            presentationLifecycle: presentationLifecycle
        )

        return assembleServices(
            inputs: inputs,
            paywallRepository: paywallRepository,
            operationGate: operationGate
        )
    }
}

private extension AdaptyMonetizationFactory {
    func assembleServices(
        inputs: AdaptyServiceInputs,
        paywallRepository: AdaptyPaywallRepository,
        operationGate: MonetizationOperationGate
    ) -> BroadMonetizationServices {
        BroadMonetizationServices(
            activate: ActivateMonetizationUseCase(
                repository: AdaptyMonetizationRepository(
                    configuration: configuration,
                    identityProvider: identityProvider,
                    context: context,
                    messages: messages
                )
            ),
            loadPaywall: LoadPaywallUseCase(
                repository: paywallRepository,
                cache: inputs.paywallCache,
                analytics: inputs.deliveryAnalytics,
                presentationLifecycle: inputs.presentationLifecycle,
                staleLoadError: inputs.errors.stalePaywallLoad
            ),
            selectProduct: SelectProductUseCase(),
            purchaseProduct: PurchaseSelectedProductUseCase(
                repository: makePurchaseRepository(
                    paywallRepository: paywallRepository
                ),
                entitlementRepository: inputs.entitlementRepository,
                analytics: inputs.deliveryAnalytics,
                pendingStore: inputs.pendingStore,
                operationGate: operationGate,
                inProgressError: inputs.errors.purchaseInProgress
            ),
            restorePurchases: RestorePurchasesUseCase(
                repository: makeRestoreRepository(),
                entitlementRepository: inputs.entitlementRepository,
                analytics: inputs.deliveryAnalytics,
                operationGate: operationGate,
                verificationUnavailableError: inputs.errors.restoreVerificationUnavailable
            ),
            analytics: inputs.deliveryAnalytics,
            paywallPresentationLifecycle: inputs.presentationLifecycle,
            operationGate: operationGate,
            pendingApplePurchase: PendingApplePurchaseCoordinator(
                store: inputs.pendingStore,
                refreshEntitlement: inputs.entitlementRepository,
                transactionRecovery: inputs.transactionRecovery,
                analytics: inputs.deliveryAnalytics,
                operationGate: operationGate
            )
        )
    }

    func makePaywallRepository() -> AdaptyPaywallRepository {
        AdaptyPaywallRepository(
            configuration: configuration,
            identityProvider: identityProvider,
            placementRegistry: placementRegistry,
            context: context,
            remoteConfigurationParser: remoteConfigurationParser,
            remoteConfigurationStore: remoteConfigurationStore,
            messages: messages
        )
    }

    func makePurchaseRepository(
        paywallRepository: any PaywallRepositoryProtocol
    ) -> AdaptyPurchaseRepository {
        AdaptyPurchaseRepository(
            configuration: configuration,
            identityProvider: identityProvider,
            context: context,
            paywallRepository: paywallRepository,
            messages: messages
        )
    }

    func makeRestoreRepository() -> AdaptyRestoreRepository {
        AdaptyRestoreRepository(
            configuration: configuration,
            identityProvider: identityProvider,
            context: context,
            messages: messages
        )
    }
}

private struct AdaptyServiceInputs: Sendable {
    let entitlementRepository: any EntitlementRepositoryProtocol
    let deliveryAnalytics: any MonetizationAnalyticsProtocol
    let paywallCache: (any PaywallCacheProtocol)?
    let errors: MonetizationFlowErrors
    let pendingStore: any PendingApplePurchaseStoreProtocol
    let transactionRecovery: any PendingAppleTransactionRecoveryProtocol
    let presentationLifecycle: any PaywallPresentationLifecycleProtocol
}
