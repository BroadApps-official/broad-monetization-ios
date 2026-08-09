public struct UnknownEntitlementStatusProvider: EntitlementStatusProviderProtocol {
    public init() {}

    public func currentStatus() async -> EntitlementStatus {
        .unknown
    }
}
