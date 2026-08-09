/// Owns provider resources attached to one concrete paywall presentation.
/// This is deliberately separate from best-effort host analytics: releasing a
/// StoreKit/Adapty handle must not depend on an analytics queue or destination.
public protocol PaywallPresentationLifecycleProtocol: Sendable {
    func presentationDidAppear(_ context: PaywallAnalyticsContext) async
    func presentationDidEnd(_ context: PaywallAnalyticsContext) async
}

public struct NoOpPaywallPresentationLifecycle: PaywallPresentationLifecycleProtocol {
    public init() {}

    public func presentationDidAppear(_: PaywallAnalyticsContext) async {}

    public func presentationDidEnd(_: PaywallAnalyticsContext) async {}
}
