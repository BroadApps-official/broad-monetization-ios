import Foundation

public enum RUBillingEntitlementClientResult: Equatable, Sendable {
    case serverValidated(RUBillingEntitlementRecord)
    case unresolved
}

public protocol RUBillingEntitlementClientProtocol: Sendable {
    func loadEntitlement(
        for subject: EntitlementSubject
    ) async -> RUBillingEntitlementClientResult
}

public struct URLSessionRUBillingEntitlementClient: RUBillingEntitlementClientProtocol {
    private let configuration: RUBillingHTTPConfiguration
    private let configuredSubject: EntitlementSubject
    private let requestEncoder: any RUEntitlementRequestEncoderProtocol
    private let responseDecoder: any RUEntitlementResponseDecoderProtocol
    private let client: RUBillingAuthenticatedHTTPClient

    public init(
        configuration: RUBillingHTTPConfiguration,
        subject: EntitlementSubject,
        authorizationProvider: any SubjectAuthorizationProviderProtocol,
        authorizationBinding: SubjectAuthorizationBinding,
        requestEncoder: any RUEntitlementRequestEncoderProtocol = BroadAppsRUBillingWireContract(),
        responseDecoder: any RUEntitlementResponseDecoderProtocol = BroadAppsRUBillingWireContract()
    ) {
        self.configuration = configuration
        configuredSubject = subject
        self.requestEncoder = requestEncoder
        self.responseDecoder = responseDecoder
        client = RUBillingAuthenticatedHTTPClient(
            configuration: configuration,
            subject: subject,
            authorizationProvider: authorizationProvider,
            authorizationBinding: authorizationBinding
        )
    }

    public func loadEntitlement(
        for subject: EntitlementSubject
    ) async -> RUBillingEntitlementClientResult {
        guard !Task.isCancelled,
              subject == configuredSubject,
              let request = try? requestEncoder.encodeEntitlementRequest(
                  applicationID: configuration.applicationID,
                  appBundleIdentifier: configuration.appBundleIdentifier
              )
        else {
            return .unresolved
        }

        let result = await client.send(
            path: configuration.endpoints.entitlementStatus,
            method: request.method,
            timeout: configuration.requestTimeouts.entitlementStatus,
            queryItems: request.queryItems,
            body: request.body
        )
        guard case let .success(response) = result,
              let record = try? responseDecoder.decodeEntitlement(
                  from: response.data,
                  subject: subject
              ),
              record.subject == subject
        else {
            return .unresolved
        }
        return .serverValidated(record)
    }
}
