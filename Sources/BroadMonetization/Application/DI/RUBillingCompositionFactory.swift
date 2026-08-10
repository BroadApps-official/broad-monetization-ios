public struct RUBillingCompositionFactory: Sendable {
    private let configuration: RUBillingCompositionConfiguration
    private let dependencies: RUBillingCompositionDependencies
    private let wire: RUBillingWireAdapters

    public init(
        configuration: RUBillingCompositionConfiguration,
        dependencies: RUBillingCompositionDependencies,
        wire: RUBillingWireAdapters = .broadApps
    ) {
        precondition(
            configuration.isFeatureEnabled,
            "Use disabled RU billing adapters instead of creating an enabled composition"
        )
        self.configuration = configuration
        self.dependencies = dependencies
        self.wire = wire
    }

    public func makeEntitlementRegistration() -> EntitlementSourceRegistration {
        let defaultClient = makeEntitlementClient()
        return RUBillingEntitlementSourceFactory(
            clients: [defaultClient] + dependencies.additionalEntitlementClients,
            authorizationBinding: dependencies.authorizationBinding,
            clock: dependencies.clock
        ).makeRegistration(
            configuration: RUBillingEntitlementSourceConfiguration(
                subject: dependencies.subject,
                freshnessPolicy: configuration.entitlementFreshness
            )
        )
    }

    public func makeServices(
        refreshEntitlement: any RefreshEntitlementUseCaseProtocol,
        operationGate: MonetizationOperationGate
    ) -> RUBillingServices {
        let storefront = makeStorefrontRepository()
        let catalog = makeCatalogRepository()
        let pendingStore = makePendingStore()
        let matcher = RUCatalogProductMatcher(
            mappingPolicy: dependencies.productMappingPolicy
        )
        let gate = RUBillingGate(
            isFeatureEnabled: configuration.isFeatureEnabled,
            remoteFallback: configuration.remoteGateFallback
        )

        return RUBillingServices(
            catalog: makeCatalogServices(
                storefront: storefront,
                catalog: catalog,
                matcher: matcher
            ),
            checkout: makeCheckoutServices(
                storefront: storefront,
                catalog: catalog,
                pendingStore: pendingStore,
                matcher: matcher,
                gate: gate,
                operationGate: operationGate,
                refreshEntitlement: refreshEntitlement
            )
        )
    }
}

private extension RUBillingCompositionFactory {
    func makeCatalogServices(
        storefront: CachedStorefrontRepository,
        catalog: CachedRUCatalogRepository,
        matcher: RUCatalogProductMatcher
    ) -> RUBillingCatalogServices {
        RUBillingCatalogServices(
            repository: catalog,
            resolveProduct: ResolveRUCatalogProductUseCase(
                catalogRepository: catalog,
                matcher: matcher
            ),
            resolveCheckoutMethods: ResolveCheckoutMethodsUseCase(
                storefrontRepository: storefront,
                catalogRepository: catalog,
                productMatcher: matcher,
                isFeatureEnabled: configuration.isFeatureEnabled,
                remoteGateFallback: configuration.remoteGateFallback
            )
        )
    }

    func makeCheckoutServices(
        storefront: CachedStorefrontRepository,
        catalog: CachedRUCatalogRepository,
        pendingStore: PendingRUCheckoutStore,
        matcher: RUCatalogProductMatcher,
        gate: RUBillingGate,
        operationGate: MonetizationOperationGate,
        refreshEntitlement: any RefreshEntitlementUseCaseProtocol
    ) -> RUBillingCheckoutServices {
        let create = CreateRUCheckoutUseCase(repository: makeCheckoutRepository())
        let flow = RUCheckoutFlowCoordinator(
            checkout: create,
            authorizationProvider: dependencies.authorizationProvider,
            storefrontRepository: storefront,
            gate: gate,
            opener: dependencies.paymentURLOpener,
            pendingStore: pendingStore,
            analytics: dependencies.analytics,
            operationGate: operationGate,
            clock: dependencies.clock
        )
        let refresh = RefreshRUPaymentUseCase(
            paymentStatusRepository: makePaymentStatusRepository(),
            refreshEntitlement: refreshEntitlement,
            authorizationBinding: dependencies.authorizationBinding,
            policy: configuration.polling
        )

        return RUBillingCheckoutServices(
            startSelectedProduct: StartSelectedRUCheckoutUseCase(
                catalogRepository: catalog,
                matcher: matcher,
                checkoutFlow: flow
            ),
            applicationReturn: RUPaymentReturnCoordinator(
                pendingStore: pendingStore,
                refreshPayment: refresh,
                operationGate: operationGate,
                analytics: dependencies.analytics
            ),
            cancelSubscription: CancelRUSubscriptionUseCase(
                repository: makeCancellationRepository(),
                refreshEntitlement: refreshEntitlement,
                authorizationBinding: dependencies.authorizationBinding
            ),
            loadSubscriptionStatus: LoadRUSubscriptionStatusUseCase(
                client: makeEntitlementClient(),
                subject: dependencies.subject,
                authorizationBinding: dependencies.authorizationBinding
            ),
            operationGate: operationGate
        )
    }

    func makeStorefrontRepository() -> CachedStorefrontRepository {
        CachedStorefrontRepository(
            cache: dependencies.cache,
            cacheTimeToLive: configuration.cache.storefrontTimeToLive,
            clock: dependencies.clock
        )
    }

    func makeCatalogRepository() -> CachedRUCatalogRepository {
        let remote = URLSessionRUCatalogRepository(
            configuration: configuration.http,
            subject: dependencies.subject,
            authorizationProvider: dependencies.authorizationProvider,
            authorizationBinding: dependencies.authorizationBinding,
            requestEncoder: wire.catalog.requestEncoder,
            decoder: wire.catalog.responseDecoder,
            clock: dependencies.clock
        )
        return CachedRUCatalogRepository(
            remote: remote,
            cache: dependencies.cache,
            subject: dependencies.subject,
            authorizationBinding: dependencies.authorizationBinding,
            freshTimeToLive: configuration.cache.catalogFreshTimeToLive,
            maximumStaleAge: configuration.cache.catalogMaximumStaleAge,
            clock: dependencies.clock
        )
    }

    func makeCheckoutRepository() -> URLSessionRUCheckoutRepository {
        URLSessionRUCheckoutRepository(
            configuration: configuration.http,
            subject: dependencies.subject,
            authorizationProvider: dependencies.authorizationProvider,
            authorizationBinding: dependencies.authorizationBinding,
            requestEncoder: wire.checkout.requestEncoder,
            responseDecoder: wire.checkout.responseDecoder
        )
    }

    func makePaymentStatusRepository() -> URLSessionRUPaymentStatusRepository {
        URLSessionRUPaymentStatusRepository(
            configuration: configuration.http,
            subject: dependencies.subject,
            authorizationProvider: dependencies.authorizationProvider,
            authorizationBinding: dependencies.authorizationBinding,
            requestEncoder: wire.paymentStatus.requestEncoder,
            responseDecoder: wire.paymentStatus.responseDecoder,
            clock: dependencies.clock
        )
    }

    func makeCancellationRepository() -> any RUSubscriptionRepositoryProtocol {
        RUCancellationRepositoryFactory(
            configuration: configuration.http,
            subject: dependencies.subject,
            authorizationProvider: dependencies.authorizationProvider,
            authorizationBinding: dependencies.authorizationBinding,
            requestEncoder: wire.cancellation.requestEncoder,
            responseDecoder: wire.cancellation.responseDecoder
        ).makeRepository()
    }

    func makeEntitlementClient() -> URLSessionRUBillingEntitlementClient {
        URLSessionRUBillingEntitlementClient(
            configuration: configuration.http,
            subject: dependencies.subject,
            authorizationProvider: dependencies.authorizationProvider,
            authorizationBinding: dependencies.authorizationBinding,
            requestEncoder: wire.entitlement.requestEncoder,
            responseDecoder: wire.entitlement.responseDecoder
        )
    }

    func makePendingStore() -> PendingRUCheckoutStore {
        PendingRUCheckoutStore(
            subject: dependencies.subject,
            applicationIdentifier: dependencies.applicationIdentifier,
            authorizationBinding: dependencies.authorizationBinding,
            cache: dependencies.cache,
            retention: configuration.cache.pendingCheckoutRetention,
            clock: dependencies.clock
        )
    }
}
