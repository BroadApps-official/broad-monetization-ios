import BroadCore

public struct RUBillingEntitlementSourceConfiguration: Sendable {
    public let subject: EntitlementSubject
    public let freshnessPolicy: EntitlementFreshnessPolicy

    public init(
        subject: EntitlementSubject,
        freshnessPolicy: EntitlementFreshnessPolicy
    ) {
        self.subject = subject
        self.freshnessPolicy = freshnessPolicy
    }
}

public struct RUBillingEntitlementSourceFactory: Sendable {
    private let clients: [any RUBillingEntitlementClientProtocol]
    private let authorizationBinding: SubjectAuthorizationBinding
    private let clock: CacheClock

    public init(
        clients: [any RUBillingEntitlementClientProtocol],
        authorizationBinding: SubjectAuthorizationBinding,
        clock: CacheClock = .system
    ) {
        precondition(
            !clients.isEmpty,
            "RU billing entitlement source needs at least one authoritative client"
        )
        self.clients = clients
        self.authorizationBinding = authorizationBinding
        self.clock = clock
    }

    public func makeRegistration(
        configuration: RUBillingEntitlementSourceConfiguration
    ) -> EntitlementSourceRegistration {
        precondition(
            authorizationBinding.subject == configuration.subject,
            "RU entitlement binding must match the exact subject"
        )
        return EntitlementSourceRegistration(
            source: .ruBilling,
            subject: configuration.subject,
            freshnessPolicy: configuration.freshnessPolicy,
            repository: RUBillingEntitlementRepository(
                clients: clients,
                authorizationBinding: authorizationBinding,
                clock: clock
            ),
            acceptanceGate: EntitlementSourceAcceptanceGate(
                // One fixed physical key stays bounded, while the record carries
                // the exact login epoch. A late old-task write can at worst make
                // the new epoch miss cache; it can never grant old access.
                cachePartition: authorizationBinding.cachePartition,
                cacheStoragePartition: authorizationBinding.cacheStoragePartition,
                isCurrent: { [authorizationBinding] in
                    authorizationBinding.isCurrent()
                }
            )
        )
    }
}
