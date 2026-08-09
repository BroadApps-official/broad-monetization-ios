import Foundation

public struct URLSessionRUCancellationRepository: RUSubscriptionRepositoryProtocol {
    private let configuration: RUBillingHTTPConfiguration
    private let endpoint: RUBillingEndpointPath
    private let requestEncoder: any RUCancellationRequestEncoderProtocol
    private let responseDecoder: any RUCancellationResponseDecoderProtocol
    private let client: RUBillingAuthenticatedHTTPClient

    public init(
        configuration: RUBillingHTTPConfiguration,
        endpoint: RUBillingEndpointPath? = nil,
        subject: EntitlementSubject,
        authorizationProvider: any SubjectAuthorizationProviderProtocol,
        authorizationBinding: SubjectAuthorizationBinding,
        requestEncoder: any RUCancellationRequestEncoderProtocol = BroadAppsRUBillingWireContract(),
        responseDecoder: any RUCancellationResponseDecoderProtocol = BroadAppsRUBillingWireContract()
    ) {
        self.configuration = configuration
        self.endpoint = endpoint ?? configuration.endpoints.cancellation
        self.requestEncoder = requestEncoder
        self.responseDecoder = responseDecoder
        client = RUBillingAuthenticatedHTTPClient(
            configuration: configuration,
            subject: subject,
            authorizationProvider: authorizationProvider,
            authorizationBinding: authorizationBinding
        )
    }

    public func cancelSubscription(
        id: RUSubscriptionID
    ) async -> RUSubscriptionCancellationOutcome {
        guard !Task.isCancelled,
              let request = try? requestEncoder.encodeCancellationRequest(
                  subscriptionID: id,
                  applicationID: configuration.applicationID,
                  appBundleIdentifier: configuration.appBundleIdentifier
              )
        else {
            return .unavailable(RUBillingSafeErrors.cancellationUnavailable)
        }

        let result = await client.send(
            path: endpoint,
            method: request.method,
            timeout: configuration.requestTimeouts.cancellation,
            queryItems: request.queryItems,
            body: request.body
        )

        switch result {
        case let .success(response):
            return (try? responseDecoder.decodeCancellationOutcome(
                from: response.data
            ))
                ?? .failed(RUBillingSafeErrors.cancellationFailed)
        case .rejected:
            return .failed(RUBillingSafeErrors.cancellationFailed)
        case .unauthorized, .unavailable:
            return .unavailable(RUBillingSafeErrors.cancellationUnavailable)
        }
    }
}
