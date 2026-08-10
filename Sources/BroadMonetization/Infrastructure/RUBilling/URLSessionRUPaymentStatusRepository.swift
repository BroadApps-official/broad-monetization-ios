import BroadCore
import Foundation

struct URLSessionRUPaymentStatusRepository: RUPaymentStatusRepositoryProtocol {
    private let configuration: RUBillingHTTPConfiguration
    private let requestEncoder: any RUPaymentStatusRequestEncoderProtocol
    private let responseDecoder: any RUPaymentStatusResponseDecoderProtocol
    private let client: RUBillingAuthenticatedHTTPClient
    private let clock: CacheClock

    init(
        configuration: RUBillingHTTPConfiguration,
        subject: EntitlementSubject,
        authorizationProvider: any SubjectAuthorizationProviderProtocol,
        authorizationBinding: SubjectAuthorizationBinding,
        requestEncoder: any RUPaymentStatusRequestEncoderProtocol = BroadAppsRUBillingWireContract(),
        responseDecoder: any RUPaymentStatusResponseDecoderProtocol = BroadAppsRUBillingWireContract(),
        clock: CacheClock = .system
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
        self.clock = clock
    }

    func paymentStatus(
        for checkoutSessionID: CheckoutSessionID
    ) async -> RUPaymentStatusOutcome {
        guard !Task.isCancelled,
              let request = try? requestEncoder.encodePaymentStatusRequest(
                  checkoutSessionID: checkoutSessionID,
                  applicationID: configuration.applicationID,
                  appBundleIdentifier: configuration.appBundleIdentifier
              )
        else {
            return .unavailable(RUBillingSafeErrors.paymentStatusUnavailable)
        }

        let result = await client.send(
            path: configuration.endpoints.paymentStatus,
            method: request.method,
            timeout: configuration.requestTimeouts.paymentStatus,
            queryItems: request.queryItems,
            body: request.body
        )
        guard case let .success(response) = result else {
            if case let .unavailable(failure) = result {
                return .unavailable(
                    RUBillingSafeErrors.network(
                        failure,
                        fallback: RUBillingSafeErrors.paymentStatusUnavailable
                    )
                )
            }
            return .unavailable(RUBillingSafeErrors.paymentStatusUnavailable)
        }
        guard let snapshot = try? responseDecoder.decodePaymentStatus(
            from: response.data,
            expectedCheckoutSessionID: checkoutSessionID,
            checkedAt: clock.now()
        ) else {
            return .unavailable(RUBillingSafeErrors.paymentStatusUnavailable)
        }
        return .resolved(snapshot)
    }
}
