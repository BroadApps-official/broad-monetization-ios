import Foundation

/// Uses the same subject-bound transport as checkout. Neither endpoint is
/// retried automatically because paywall-shown is not server-deduplicated.
public struct URLSessionRUExperimentRepository: RUExperimentRepositoryProtocol {
    private let client: RUBillingAuthenticatedHTTPClient
    private let configuration: RUExperimentHTTPConfiguration

    public init(
        http: RUBillingHTTPConfiguration,
        configuration: RUExperimentHTTPConfiguration,
        subject: EntitlementSubject,
        authorizationProvider: any SubjectAuthorizationProviderProtocol,
        authorizationBinding: SubjectAuthorizationBinding
    ) {
        client = RUBillingAuthenticatedHTTPClient(
            configuration: http,
            subject: subject,
            authorizationProvider: authorizationProvider,
            authorizationBinding: authorizationBinding
        )
        self.configuration = configuration
    }

    init(client: RUBillingAuthenticatedHTTPClient, configuration: RUExperimentHTTPConfiguration) {
        self.client = client
        self.configuration = configuration
    }

    public func assign(_ event: RUExperimentEvent) async -> RUExperimentAssignOutcome {
        switch await send(event, path: configuration.assign) {
        case let .success(response):
            guard let wire = try? JSONDecoder().decode(RUExperimentAssignResponse.self, from: response.data),
                  let metadata = RUExperimentMetadata(
                      experimentCode: event.experimentCode, segmentCode: wire.segment.code
                  ),
                  wire.requestedSegmentMatches == (event.segmentCode == wire.segment.code)
            else {
                return .rejected
            }
            return .assigned(RUExperimentAssignedSegment(
                metadata: metadata,
                requestedSegmentMatches: wire.requestedSegmentMatches,
                isControl: wire.segment.isControl,
                created: wire.created
            ))
        case .unauthorized: return .unauthorized
        case .unavailable: return .unavailable
        case .rejected: return .rejected
        }
    }

    public func paywallShown(_ event: RUExperimentEvent) async -> RUExperimentShownOutcome {
        switch await send(event, path: configuration.paywallShown) {
        case let .success(response):
            guard let wire = try? JSONDecoder().decode(RUExperimentShownResponse.self, from: response.data),
                  wire.logged
            else {
                return .rejected
            }
            return .logged
        case .unauthorized: return .unauthorized
        case .unavailable: return .unavailable
        case .rejected: return .rejected
        }
    }

    private func send(_ event: RUExperimentEvent, path: RUBillingEndpointPath) async -> RUBillingHTTPClientResult {
        guard let body = try? JSONEncoder().encode(event) else {
            return .rejected
        }
        return await client.send(
            path: path, method: .post, timeout: configuration.requestTimeout, body: body
        )
    }
}

private struct RUExperimentAssignResponse: Decodable {
    struct Segment: Decodable {
        let code: String
        let isControl: Bool
    }

    let segment: Segment
    let requestedSegmentMatches: Bool
    let created: Bool
}

private struct RUExperimentShownResponse: Decodable {
    let logged: Bool
}
