import BroadCore
import Foundation

public struct RUBillingCacheConfiguration: Equatable, Sendable {
    public let storefrontTimeToLive: TimeInterval
    public let catalogFreshTimeToLive: TimeInterval
    public let catalogMaximumStaleAge: TimeInterval
    public let pendingCheckoutRetention: TimeInterval

    public init(
        storefrontTimeToLive: TimeInterval = 24 * 60 * 60,
        catalogFreshTimeToLive: TimeInterval = 15 * 60,
        catalogMaximumStaleAge: TimeInterval = 24 * 60 * 60,
        pendingCheckoutRetention: TimeInterval = 24 * 60 * 60
    ) {
        let positiveValues = [
            storefrontTimeToLive,
            catalogFreshTimeToLive,
            pendingCheckoutRetention
        ]
        precondition(
            positiveValues.allSatisfy { $0.isFinite && $0 > 0 },
            "RU billing cache intervals must be finite and positive"
        )
        precondition(
            catalogMaximumStaleAge.isFinite && catalogMaximumStaleAge >= catalogFreshTimeToLive,
            "RU catalog stale age must be finite and at least its fresh time to live"
        )

        self.storefrontTimeToLive = storefrontTimeToLive
        self.catalogFreshTimeToLive = catalogFreshTimeToLive
        self.catalogMaximumStaleAge = catalogMaximumStaleAge
        self.pendingCheckoutRetention = pendingCheckoutRetention
    }
}

public struct RUBillingCompositionConfiguration: Sendable {
    public let http: RUBillingHTTPConfiguration
    public let entitlementFreshness: EntitlementFreshnessPolicy
    public let isFeatureEnabled: Bool
    public let remoteGateFallback: RUBillingRemoteGateFallbackPolicy
    public let polling: RUPaymentPollingPolicy
    public let cache: RUBillingCacheConfiguration

    public init(
        http: RUBillingHTTPConfiguration,
        entitlementFreshness: EntitlementFreshnessPolicy,
        isFeatureEnabled: Bool,
        remoteGateFallback: RUBillingRemoteGateFallbackPolicy = .disabled,
        polling: RUPaymentPollingPolicy = RUPaymentPollingPolicy(),
        cache: RUBillingCacheConfiguration = RUBillingCacheConfiguration()
    ) {
        self.http = http
        self.entitlementFreshness = entitlementFreshness
        self.isFeatureEnabled = isFeatureEnabled
        self.remoteGateFallback = remoteGateFallback
        self.polling = polling
        self.cache = cache
    }
}

public struct RUBillingCompositionDependencies: Sendable {
    public let subject: EntitlementSubject
    public let applicationIdentifier: String
    public let authorizationProvider: any SubjectAuthorizationProviderProtocol
    let authorizationBinding: SubjectAuthorizationBinding
    public let cache: any CacheRepositoryProtocol
    public let analytics: any MonetizationAnalyticsProtocol
    public let paymentURLOpener: any PaymentURLOpenerProtocol
    public let productMappingPolicy: any RUCatalogProductMappingPolicyProtocol
    public let additionalEntitlementClients: [any RUBillingEntitlementClientProtocol]
    public let clock: CacheClock

    public init(
        subject: EntitlementSubject,
        applicationIdentifier: String,
        authorizationProvider: any SubjectAuthorizationProviderProtocol,
        authorizationBinding: SubjectAuthorizationBinding,
        cache: any CacheRepositoryProtocol,
        analytics: any MonetizationAnalyticsProtocol = NoOpMonetizationAnalytics(),
        paymentURLOpener: any PaymentURLOpenerProtocol = UIApplicationPaymentURLOpener(),
        productMappingPolicy: any RUCatalogProductMappingPolicyProtocol =
            ExactOnlyRUCatalogProductMappingPolicy(),
        additionalEntitlementClients: [any RUBillingEntitlementClientProtocol] = [],
        clock: CacheClock = .system
    ) {
        precondition(
            MonetizationIdentifierPolicy.isValid(applicationIdentifier),
            "Application identifier must be valid"
        )
        precondition(
            authorizationBinding.subject == subject,
            "RU authorization binding must match the exact subject"
        )
        self.subject = subject
        self.applicationIdentifier = applicationIdentifier
        self.authorizationProvider = authorizationProvider
        self.authorizationBinding = authorizationBinding
        self.cache = cache
        self.analytics = NonBlockingMonetizationAnalytics.wrapping(analytics)
        self.paymentURLOpener = paymentURLOpener
        self.productMappingPolicy = productMappingPolicy
        self.additionalEntitlementClients = additionalEntitlementClients
        self.clock = clock
    }
}

public struct RUBillingCatalogServices: Sendable {
    public let repository: any RUCatalogRepositoryProtocol
    public let resolveProduct: ResolveRUCatalogProductUseCase
    public let resolveCheckoutMethods: any ResolveCheckoutMethodsUseCaseProtocol
}

public struct RUBillingCheckoutServices: Sendable {
    public let startSelectedProduct: any StartSelectedRUCheckoutUseCaseProtocol
    public let applicationReturn: RUPaymentReturnCoordinator
    public let cancelSubscription: any CancelRUSubscriptionUseCaseProtocol
    public let loadSubscriptionStatus:
        any LoadRUSubscriptionStatusUseCaseProtocol
    public let operationGate: MonetizationOperationGate
}

public struct RUBillingServices: Sendable {
    public let catalog: RUBillingCatalogServices
    public let checkout: RUBillingCheckoutServices
}
