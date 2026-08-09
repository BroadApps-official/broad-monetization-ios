public struct RUCancellationRepositoryFactory: Sendable {
    private let configuration: RUBillingHTTPConfiguration
    private let subject: EntitlementSubject
    private let authorizationProvider: any SubjectAuthorizationProviderProtocol
    private let authorizationBinding: SubjectAuthorizationBinding
    private let requestEncoder: any RUCancellationRequestEncoderProtocol
    private let responseDecoder: any RUCancellationResponseDecoderProtocol

    public init(
        configuration: RUBillingHTTPConfiguration,
        subject: EntitlementSubject,
        authorizationProvider: any SubjectAuthorizationProviderProtocol,
        authorizationBinding: SubjectAuthorizationBinding,
        requestEncoder: any RUCancellationRequestEncoderProtocol = BroadAppsRUBillingWireContract(),
        responseDecoder: any RUCancellationResponseDecoderProtocol = BroadAppsRUBillingWireContract()
    ) {
        self.configuration = configuration
        self.subject = subject
        self.authorizationProvider = authorizationProvider
        self.authorizationBinding = authorizationBinding
        self.requestEncoder = requestEncoder
        self.responseDecoder = responseDecoder
    }

    public func makeRepository() -> any RUSubscriptionRepositoryProtocol {
        let primary = makeHTTPRepository(endpoint: configuration.endpoints.cancellation)
        guard configuration.allowsLegacyCancellationFallback,
              let legacyEndpoint = configuration.endpoints.legacyCancellation
        else {
            return primary
        }

        return FallbackRUSubscriptionRepository(
            primary: primary,
            legacy: makeHTTPRepository(endpoint: legacyEndpoint),
            allowsLegacyFallback: true
        )
    }
}

private extension RUCancellationRepositoryFactory {
    func makeHTTPRepository(
        endpoint: RUBillingEndpointPath
    ) -> URLSessionRUCancellationRepository {
        URLSessionRUCancellationRepository(
            configuration: configuration,
            endpoint: endpoint,
            subject: subject,
            authorizationProvider: authorizationProvider,
            authorizationBinding: authorizationBinding,
            requestEncoder: requestEncoder,
            responseDecoder: responseDecoder
        )
    }
}
