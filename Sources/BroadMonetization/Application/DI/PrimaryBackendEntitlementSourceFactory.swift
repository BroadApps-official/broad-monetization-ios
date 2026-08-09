import BroadCore

public struct PrimaryBackendSourceConfiguration: Sendable {
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

public struct PrimaryBackendEntitlementSourceFactory: Sendable {
    private let client: any PrimaryBackendEntitlementClientProtocol
    private let clock: CacheClock

    public init(
        client: any PrimaryBackendEntitlementClientProtocol,
        clock: CacheClock = .system
    ) {
        self.client = client
        self.clock = clock
    }

    public func makeRegistration(
        configuration: PrimaryBackendSourceConfiguration
    ) -> EntitlementSourceRegistration {
        EntitlementSourceRegistration(
            source: .primaryBackend,
            subject: configuration.subject,
            freshnessPolicy: configuration.freshnessPolicy,
            repository: PrimaryBackendEntitlementRepository(
                client: client,
                clock: clock
            )
        )
    }
}
