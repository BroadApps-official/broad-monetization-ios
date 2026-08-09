public protocol RefreshEntitlementUseCaseProtocol: Sendable {
    func callAsFunction(
        policy: EntitlementRefreshPolicy
    ) async -> EntitlementSnapshot
}

public extension RefreshEntitlementUseCaseProtocol {
    func callAsFunction() async -> EntitlementSnapshot {
        await callAsFunction(policy: .joinInFlight)
    }
}
