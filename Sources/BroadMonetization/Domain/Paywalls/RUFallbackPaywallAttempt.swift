/// Evidence from this provider request, including a configuration received
/// before StoreKit products failed to load. Never reconstruct it from disk.
public struct RUFallbackPaywallAttempt: Sendable {
    public enum Availability: Sendable {
        case available
        case notConfigured
        case unavailable(receivedConfiguration: RemotePaywallConfiguration?)
    }

    public let outcome: PaywallLoadOutcome
    public let availability: Availability

    public init(outcome: PaywallLoadOutcome, availability: Availability) {
        self.outcome = outcome
        self.availability = availability
    }
}

/// Opt-in provider boundary. Existing PaywallRepositoryProtocol callers keep
/// their original loading and cache behavior.
public protocol RUFallbackPaywallRepositoryProtocol: PaywallRepositoryProtocol {
    func loadRUFallbackAttempt(for placementID: PlacementID) async -> RUFallbackPaywallAttempt
}
