import BroadCore

/// Reads entitlementStatus (normally GET /v1/policy/effective), without cache.
public struct URLSessionRUAccountPolicyRepository: RUAccountPolicyRepositoryProtocol {
    private let configuration: RUBillingHTTPConfiguration
    private let subject: EntitlementSubject
    private let client: RUBillingAuthenticatedHTTPClient

    public init(
        configuration: RUBillingHTTPConfiguration,
        subject: EntitlementSubject,
        authorizationProvider: any SubjectAuthorizationProviderProtocol,
        authorizationBinding: SubjectAuthorizationBinding
    ) {
        self.configuration = configuration
        self.subject = subject
        client = RUBillingAuthenticatedHTTPClient(
            configuration: configuration, subject: subject,
            authorizationProvider: authorizationProvider, authorizationBinding: authorizationBinding
        )
    }

    public func loadPolicy(for subject: EntitlementSubject) async -> RUAccountPolicyOutcome {
        guard subject == self.subject else { return .unavailable(RUBillingSafeErrors.paymentStatusUnavailable) }
        let result = await client.send(
            path: configuration.endpoints.entitlementStatus, method: .get,
            timeout: configuration.requestTimeouts.entitlementStatus
        )
        guard case let .success(response) = result,
              let policy = try? BroadAppsAccountPolicyWireContract().decodePolicy(from: response.data, subject: subject)
        else { return .unavailable(RUBillingSafeErrors.paymentStatusUnavailable) }
        return .loaded(policy)
    }

    init(configuration: RUBillingHTTPConfiguration, subject: EntitlementSubject, client: RUBillingAuthenticatedHTTPClient) {
        self.configuration = configuration
        self.subject = subject
        self.client = client
    }
}
