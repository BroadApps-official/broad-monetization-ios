import Foundation

struct URLSessionRUCheckoutRepository: RUCheckoutRepositoryProtocol {
    private let configuration: RUBillingHTTPConfiguration
    private let requestEncoder: any RUCheckoutRequestEncoderProtocol
    private let responseDecoder: any RUCheckoutResponseDecoderProtocol
    private let client: RUBillingAuthenticatedHTTPClient

    init(
        configuration: RUBillingHTTPConfiguration,
        subject: EntitlementSubject,
        authorizationProvider: any SubjectAuthorizationProviderProtocol,
        authorizationBinding: SubjectAuthorizationBinding,
        requestEncoder: any RUCheckoutRequestEncoderProtocol = BroadAppsRUBillingWireContract(),
        responseDecoder: any RUCheckoutResponseDecoderProtocol = BroadAppsRUBillingWireContract()
    ) {
        self.configuration = configuration
        self.requestEncoder = requestEncoder
        self.responseDecoder = responseDecoder
        client = RUBillingAuthenticatedHTTPClient(
            configuration: configuration,
            subject: subject,
            authorizationProvider: authorizationProvider,
            authorizationBinding: authorizationBinding
        )
    }

    func createCheckout(
        _ request: RUCheckoutRequest
    ) async -> RUCheckoutCreationOutcome {
        guard !Task.isCancelled,
              let wireRequest = try? await requestEncoder.encodeCheckoutRequest(
                  request,
                  applicationID: configuration.applicationID,
                  appBundleIdentifier: configuration.appBundleIdentifier
              )
        else {
            return .unavailable(RUBillingSafeErrors.checkoutUnavailable)
        }

        let result = await client.send(
            path: configuration.endpoints.checkout,
            method: wireRequest.method,
            timeout: configuration.requestTimeouts.checkout,
            queryItems: wireRequest.queryItems,
            body: wireRequest.body
        )

        switch result {
        case let .success(response):
            guard let session = try? responseDecoder.decodeCheckoutSession(
                from: response.data
            ) else {
                return .failed(RUBillingSafeErrors.checkoutFailed)
            }
            return .created(
                session,
                authorizationProof: response.authorizationProof
            )
        case .rejected:
            return .failed(RUBillingSafeErrors.checkoutFailed)
        case .unauthorized, .unavailable:
            return .unavailable(RUBillingSafeErrors.checkoutUnavailable)
        }
    }
}
