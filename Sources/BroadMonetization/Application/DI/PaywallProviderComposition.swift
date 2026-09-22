import BroadCore

/// Optional alternative loader; the base package never imports provider modules.
public protocol PaywallLoaderFactoryProtocol: Sendable {
    func makePaywallLoader(
        provider: any ProviderPaywallAttemptRepositoryProtocol,
        cache: (any PaywallCacheProtocol)?,
        presentationLifecycle: any PaywallPresentationLifecycleProtocol,
        staleLoadError: AppError
    ) -> any LoadPaywallUseCaseProtocol
}

public enum PaywallViewReportingDecision: Sendable {
    case usePrimaryProvider
    case handledByExtension
}

public protocol PaywallViewReportingPolicyProtocol: Sendable {
    /// Reserve before returning. Delivery may continue after dismissal.
    func reserveReport(_ context: PaywallAnalyticsContext, placement: String) async -> Task<PaywallViewReportingDecision, Never>
    func presentationDidEnd(_ presentationID: PaywallPresentationID) async
}
