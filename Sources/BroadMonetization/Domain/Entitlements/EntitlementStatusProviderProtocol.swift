public protocol EntitlementStatusProviderProtocol: Sendable {
    func currentStatus() async -> EntitlementStatus
}
