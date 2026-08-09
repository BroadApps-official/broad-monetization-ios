import BroadCore

public struct AppleEntitlementSourceConfiguration: Sendable {
    public let subject: EntitlementSubject
    public let freshnessPolicy: EntitlementFreshnessPolicy
    public let appBundleIdentifier: String
    public let productCatalog: ApplePremiumProductCatalog
    public let ownershipPolicy: StoreKitEntitlementOwnershipPolicy

    public init(
        subject: EntitlementSubject,
        freshnessPolicy: EntitlementFreshnessPolicy,
        appBundleIdentifier: String,
        productCatalog: ApplePremiumProductCatalog,
        ownershipPolicy: StoreKitEntitlementOwnershipPolicy
    ) {
        self.subject = subject
        self.freshnessPolicy = freshnessPolicy
        self.appBundleIdentifier = appBundleIdentifier
        self.productCatalog = productCatalog
        self.ownershipPolicy = ownershipPolicy
    }
}

public struct AppleEntitlementSourceFactory: Sendable {
    private let storeKitClient: any StoreKitEntitlementsClientProtocol
    private let clock: CacheClock

    public init(
        storeKitClient: any StoreKitEntitlementsClientProtocol = StoreKitCurrentEntitlementsClient(),
        clock: CacheClock = .system
    ) {
        self.storeKitClient = storeKitClient
        self.clock = clock
    }

    public func makeRegistration(
        configuration: AppleEntitlementSourceConfiguration,
        additionalAuthoritativeVerifiers: [any AppleEntitlementVerifierProtocol] = []
    ) -> EntitlementSourceRegistration {
        let storeKitVerifier = StoreKitAppleEntitlementVerifier(
            configuration: StoreKitAppleEntitlementConfiguration(
                subject: configuration.subject,
                appBundleIdentifier: configuration.appBundleIdentifier,
                productCatalog: configuration.productCatalog,
                ownershipPolicy: configuration.ownershipPolicy
            ),
            client: storeKitClient,
            clock: clock
        )
        let verifiers: [any AppleEntitlementVerifierProtocol] = [storeKitVerifier]
            + additionalAuthoritativeVerifiers

        return EntitlementSourceRegistration(
            source: .apple,
            subject: configuration.subject,
            freshnessPolicy: configuration.freshnessPolicy,
            repository: AppleEntitlementRepository(verifiers: verifiers)
        )
    }
}
