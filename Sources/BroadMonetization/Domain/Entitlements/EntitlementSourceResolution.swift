/// A result obtained from a current authoritative source check.
/// SDK-local cached data without a trustworthy validation moment must map to `unresolved`.
public enum EntitlementSourceResolution: Equatable, Sendable {
    case active(EntitlementActiveValidity)
    case inactive
    case unresolved
}
