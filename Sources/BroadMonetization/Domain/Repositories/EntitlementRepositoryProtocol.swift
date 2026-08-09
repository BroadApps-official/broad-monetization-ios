public protocol EntitlementRepositoryProtocol: Sendable {
    func refreshEntitlement(
        policy: EntitlementRefreshPolicy
    ) async -> EntitlementSnapshot

    func latestEntitlement() async -> EntitlementSnapshot?
}

public extension EntitlementRepositoryProtocol {
    func refreshEntitlement() async -> EntitlementSnapshot {
        await refreshEntitlement(policy: .joinInFlight)
    }
}
