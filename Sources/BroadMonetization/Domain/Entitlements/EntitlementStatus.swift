public enum EntitlementStatus: Equatable, Sendable {
    case active
    case inactive
    case unknown

    /// Canonical value for a diagnostics "Subscription" field, such as the one in
    /// a support email. Gives every app one agreed string instead of an ad-hoc one.
    public var supportSubscriptionValue: String {
        switch self {
        case .active:
            "subscribed"
        case .inactive:
            "not_subscribed"
        case .unknown:
            "unknown"
        }
    }
}
