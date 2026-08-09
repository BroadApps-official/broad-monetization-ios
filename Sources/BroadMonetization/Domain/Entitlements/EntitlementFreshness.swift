public enum EntitlementFreshness: Equatable, Sendable {
    case refreshed
    case cached
    case grace
    case unresolved
}
