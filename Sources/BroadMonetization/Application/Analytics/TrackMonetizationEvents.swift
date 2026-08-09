public struct TrackPaywallEventUseCase: TrackPaywallEventUseCaseProtocol {
    private let analytics: any MonetizationAnalyticsProtocol
    private let presentationLifecycle: any PaywallPresentationLifecycleProtocol

    public init(
        analytics: any MonetizationAnalyticsProtocol,
        presentationLifecycle: any PaywallPresentationLifecycleProtocol
    ) {
        self.analytics = NonBlockingMonetizationAnalytics.wrapping(analytics)
        self.presentationLifecycle = presentationLifecycle
    }

    public func callAsFunction(
        _ event: MonetizationAnalyticsEvent
    ) async {
        switch event {
        case let .paywallShown(context):
            await presentationLifecycle.presentationDidAppear(context)
        case let .paywallClosed(context, _):
            await presentationLifecycle.presentationDidEnd(context)
        default:
            break
        }
        await analytics.track(event)
    }
}

public struct TrackPaywallShownUseCase {
    private let analytics: any MonetizationAnalyticsProtocol
    private let presentationLifecycle: any PaywallPresentationLifecycleProtocol

    public init(
        analytics: any MonetizationAnalyticsProtocol,
        presentationLifecycle: any PaywallPresentationLifecycleProtocol
    ) {
        self.analytics = NonBlockingMonetizationAnalytics.wrapping(analytics)
        self.presentationLifecycle = presentationLifecycle
    }

    public func callAsFunction(
        _ paywall: PaywallPayload
    ) async {
        let context = PaywallAnalyticsContext(paywall: paywall)
        await presentationLifecycle.presentationDidAppear(context)
        await analytics.track(.paywallShown(context))
    }
}

public struct TrackPaywallClosedUseCase {
    private let analytics: any MonetizationAnalyticsProtocol
    private let presentationLifecycle: any PaywallPresentationLifecycleProtocol

    public init(
        analytics: any MonetizationAnalyticsProtocol,
        presentationLifecycle: any PaywallPresentationLifecycleProtocol
    ) {
        self.analytics = NonBlockingMonetizationAnalytics.wrapping(analytics)
        self.presentationLifecycle = presentationLifecycle
    }

    public func callAsFunction(
        _ paywall: PaywallPayload,
        reason: PaywallCloseReason
    ) async {
        let context = PaywallAnalyticsContext(paywall: paywall)
        await presentationLifecycle.presentationDidEnd(context)
        await analytics.track(
            .paywallClosed(
                context,
                reason: reason
            )
        )
    }
}

public struct TrackProductSelectedUseCase {
    private let analytics: any MonetizationAnalyticsProtocol

    public init(
        analytics: any MonetizationAnalyticsProtocol
    ) {
        self.analytics = NonBlockingMonetizationAnalytics.wrapping(analytics)
    }

    public func callAsFunction(
        _ selection: ProductSelection,
        in paywall: PaywallPayload
    ) async {
        guard selection.paywallPresentationID == paywall.presentationID,
              paywall.products.contains(selection.product)
        else {
            return
        }

        await analytics.track(
            .productSelected(
                PaywallAnalyticsContext(paywall: paywall),
                product: ProductAnalyticsContext(product: selection.product)
            )
        )
    }
}

public struct TrackPurchaseStartedUseCase {
    private let analytics: any MonetizationAnalyticsProtocol

    public init(
        analytics: any MonetizationAnalyticsProtocol
    ) {
        self.analytics = NonBlockingMonetizationAnalytics.wrapping(analytics)
    }

    public func callAsFunction(
        attemptID: MonetizationAttemptID,
        selection: ProductSelection,
        checkoutMethod: CheckoutMethod
    ) async {
        await analytics.track(
            .purchaseStarted(
                PurchaseAnalyticsContext(
                    attemptID: attemptID,
                    selection: selection,
                    checkoutMethod: checkoutMethod
                )
            )
        )
    }
}

public struct TrackPurchaseOutcomeUseCase {
    private let analytics: any MonetizationAnalyticsProtocol

    public init(
        analytics: any MonetizationAnalyticsProtocol
    ) {
        self.analytics = NonBlockingMonetizationAnalytics.wrapping(analytics)
    }

    public func callAsFunction(
        _ outcome: PurchaseOutcome,
        attemptID: MonetizationAttemptID,
        selection: ProductSelection,
        checkoutMethod: CheckoutMethod
    ) async {
        let context = PurchaseAnalyticsContext(
            attemptID: attemptID,
            selection: selection,
            checkoutMethod: checkoutMethod
        )
        let event: MonetizationAnalyticsEvent = switch outcome {
        case .activated:
            .purchaseSuccess(context)
        case .completed:
            .purchaseSuccess(context)
        case .completedButUnverified:
            .purchaseCompletedButUnverified(context)
        case .cancelled:
            .purchaseCancelled(context)
        case .pending:
            .purchasePending(context)
        case let .failed(error):
            .purchaseFailed(
                context,
                failure: MonetizationAnalyticsFailure(error: error)
            )
        }

        await analytics.track(event)
    }
}
