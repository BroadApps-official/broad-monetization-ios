public protocol EntitlementCacheProtocol: Sendable {
    func read(
        for scope: EntitlementCacheScope
    ) async throws -> EntitlementSourceAssertion?

    func write(
        _ assertion: EntitlementSourceAssertion,
        for scope: EntitlementCacheScope
    ) async throws
}
