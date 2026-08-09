public extension EntitlementEngine {
    func currentStatus() async -> EntitlementStatus {
        switch await refreshEntitlement(policy: .joinInFlight).state {
        case .active:
            .active
        case .inactive:
            .inactive
        case .unresolved:
            .unknown
        }
    }
}
