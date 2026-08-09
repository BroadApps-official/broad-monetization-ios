import BroadCore

public enum RemoteConfigurationLoadOutcome: Equatable, Sendable {
    case loaded(RemotePaywallConfiguration)
    case missing
    case unavailable(AppError)
}
