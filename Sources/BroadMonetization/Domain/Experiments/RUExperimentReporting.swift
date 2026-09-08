/// Both backend endpoints receive the same body. Authentication supplies the
/// subject; no user, device, SDK profile or payment identifier is serialized.
public struct RUExperimentEvent: Encodable, Equatable, Sendable {
    public let experimentCode: String
    public let segmentCode: String
    public let placement: String

    public init?(metadata: RUExperimentMetadata, placement: String) {
        guard RUExperimentMetadata.isValidCode(placement) else {
            return nil
        }
        experimentCode = metadata.experimentCode
        segmentCode = metadata.segmentCode
        self.placement = placement
    }
}

public struct RUExperimentAssignedSegment: Decodable, Equatable, Sendable {
    public let metadata: RUExperimentMetadata
    public let requestedSegmentMatches: Bool
    public let isControl: Bool
    public let created: Bool

    public init(
        metadata: RUExperimentMetadata,
        requestedSegmentMatches: Bool,
        isControl: Bool,
        created: Bool
    ) {
        self.metadata = metadata
        self.requestedSegmentMatches = requestedSegmentMatches
        self.isControl = isControl
        self.created = created
    }
}

public enum RUExperimentAssignOutcome: Equatable, Sendable {
    case assigned(RUExperimentAssignedSegment)
    case unavailable
    case unauthorized
    case rejected
}

public enum RUExperimentShownOutcome: Equatable, Sendable {
    case logged
    case unavailable
    case unauthorized
    case rejected
}

public protocol RUExperimentRepositoryProtocol: Sendable {
    func assign(_ event: RUExperimentEvent) async -> RUExperimentAssignOutcome
    func paywallShown(_ event: RUExperimentEvent) async -> RUExperimentShownOutcome
}

/// A failed RU report never falls through to the Adapty impression counter.
public enum RUExperimentTrackingOutcome: Equatable, Sendable {
    case useAdapty
    case outsideExperiment
    case invalidPlacement
    case presentationEnded
    case authorizationUnavailable
    case assignmentFailed
    case impressionFailed
    case reported(requestedSegmentMatches: Bool)
}
