public enum ResolvedEntitlementState: Codable, Equatable, Sendable {
    case active(EntitlementActiveValidity)
    case inactive
}
