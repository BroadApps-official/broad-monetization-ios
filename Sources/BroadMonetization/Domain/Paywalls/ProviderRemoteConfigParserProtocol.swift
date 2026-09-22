import Foundation

/// Optional provider parsing. Alias groups are atomic during main-key fallback.
/// Parsed values are live-response metadata and never revive from disk cache.
public protocol ProviderRemoteConfigParserProtocol: Sendable {
    var providerID: String { get }
    var fallbackKeyGroups: [[String]] { get }
    func parse(_ dictionary: [String: Any]) -> ProviderRemoteConfiguration?
}

/// Decision data stays available as evidence even when it cannot authorize a
/// feature. Live metadata (for example reporting attribution) is discarded when
/// a payload is qualified as untrusted. Neither part restores from disk cache.
public struct ProviderRemoteConfiguration: Equatable, Sendable {
    public let decisionData: Data
    public let liveMetadata: Data?
    public init(decisionData: Data, liveMetadata: Data? = nil) {
        self.decisionData = decisionData
        self.liveMetadata = liveMetadata
    }
}
