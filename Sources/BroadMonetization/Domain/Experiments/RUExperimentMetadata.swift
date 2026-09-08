import Foundation

/// Codes belong to the displayed Adapty variant and the backend experiment.
/// They never identify a user and never choose or randomize a variant.
public struct RUExperimentMetadata: Codable, Equatable, Sendable {
    public let experimentCode: String
    public let segmentCode: String

    public init?(experimentCode: String, segmentCode: String) {
        guard Self.isValidCode(experimentCode), Self.isValidCode(segmentCode) else {
            return nil
        }
        self.experimentCode = experimentCode
        self.segmentCode = segmentCode
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let experiment = try values.decode(String.self, forKey: .experimentCode)
        let segment = try values.decode(String.self, forKey: .segmentCode)
        guard let metadata = Self(experimentCode: experiment, segmentCode: segment) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid RU experiment codes")
            )
        }
        self = metadata
    }

    public static func isValidCode(_ value: String) -> Bool {
        (1 ... 64).contains(value.count)
            && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
}
