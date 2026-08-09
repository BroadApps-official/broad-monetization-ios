import BroadCore
import Foundation

public struct URLSessionRUCatalogRepository: RUCatalogRepositoryProtocol {
    private let configuration: RUBillingHTTPConfiguration
    private let requestEncoder: any RUCatalogRequestEncoderProtocol
    private let decoder: any RUCatalogResponseDecoderProtocol
    private let client: RUBillingAuthenticatedHTTPClient
    private let clock: CacheClock

    public init(
        configuration: RUBillingHTTPConfiguration,
        subject: EntitlementSubject,
        authorizationProvider: any SubjectAuthorizationProviderProtocol,
        authorizationBinding: SubjectAuthorizationBinding,
        requestEncoder: any RUCatalogRequestEncoderProtocol = BroadAppsRUBillingWireContract(),
        decoder: any RUCatalogResponseDecoderProtocol = BroadAppsRUCatalogResponseDecoder(),
        clock: CacheClock = .system
    ) {
        self.configuration = configuration
        self.requestEncoder = requestEncoder
        self.decoder = decoder
        client = RUBillingAuthenticatedHTTPClient(
            configuration: configuration,
            subject: subject,
            authorizationProvider: authorizationProvider,
            authorizationBinding: authorizationBinding
        )
        self.clock = clock
    }

    public func loadCatalog() async -> RUCatalogLoadOutcome {
        guard let request = try? requestEncoder.encodeCatalogRequest(
            applicationID: configuration.applicationID,
            appBundleIdentifier: configuration.appBundleIdentifier
        ) else {
            return .unavailable(RUBillingSafeErrors.catalogUnavailable)
        }

        let result = await client.send(
            path: configuration.endpoints.catalog,
            method: request.method,
            timeout: configuration.requestTimeouts.catalog,
            queryItems: request.queryItems,
            body: request.body
        )

        let fetchedAt = clock.now()
        guard fetchedAt.timeIntervalSinceReferenceDate.isFinite,
              case let .success(response) = result,
              let payload = try? decoder.decodeCatalog(
                  from: response.data,
                  fetchedAt: fetchedAt
              ),
              payload.fetchedAt.timeIntervalSinceReferenceDate.isFinite,
              payload.fetchedAt <= fetchedAt
        else {
            return .unavailable(RUBillingSafeErrors.catalogUnavailable)
        }
        return .loaded(payload)
    }
}
