/// Prevents duplicate impression and purchase lifecycle events before they reach
/// one or more analytics providers. The reservation happens before the downstream
/// `await`, so concurrent calls cannot emit the same event twice.
public actor DeduplicatingMonetizationAnalytics: MonetizationAnalyticsProtocol {
    private enum EventKey: Hashable {
        case paywallShown(PaywallPresentationID)
        case purchaseStarted(MonetizationAttemptID)
        case purchaseSuccess(MonetizationAttemptID)
        case purchaseUnverified(MonetizationAttemptID)
        case purchaseCancelled(MonetizationAttemptID)
        case purchasePending(MonetizationAttemptID)
        case purchaseFailed(MonetizationAttemptID)
        case entitlementResolved(MonetizationAttemptID)
    }

    private let destination: any MonetizationAnalyticsProtocol
    private let retainedKeyLimit: Int

    private var retainedKeys: Set<EventKey> = []
    private var retainedKeyOrder: [EventKey] = []

    public init(
        destination: any MonetizationAnalyticsProtocol,
        retainedKeyLimit: Int = 2048
    ) {
        precondition(retainedKeyLimit > 0, "Analytics deduplication limit must be positive")
        self.destination = destination
        self.retainedKeyLimit = retainedKeyLimit
    }

    public func track(
        _ event: MonetizationAnalyticsEvent
    ) async {
        if let key = Self.deduplicationKey(for: event), !reserve(key) {
            return
        }

        await destination.track(event)
    }
}

private extension DeduplicatingMonetizationAnalytics {
    private func reserve(_ key: EventKey) -> Bool {
        guard retainedKeys.insert(key).inserted else {
            return false
        }

        retainedKeyOrder.append(key)
        if retainedKeyOrder.count > retainedKeyLimit {
            let removedKey = retainedKeyOrder.removeFirst()
            retainedKeys.remove(removedKey)
        }
        return true
    }

    private static func deduplicationKey(
        for event: MonetizationAnalyticsEvent
    ) -> EventKey? {
        switch event {
        case let .paywallShown(context):
            .paywallShown(context.presentationID)
        case let .purchaseStarted(context):
            .purchaseStarted(context.attemptID)
        case let .purchaseSuccess(context):
            .purchaseSuccess(context.attemptID)
        case let .purchaseCompletedButUnverified(context):
            .purchaseUnverified(context.attemptID)
        case let .purchaseCancelled(context):
            .purchaseCancelled(context.attemptID)
        case let .purchasePending(context):
            .purchasePending(context.attemptID)
        case let .purchaseFailed(context, _):
            .purchaseFailed(context.attemptID)
        case let .entitlementResolved(context):
            .entitlementResolved(context.attemptID)
        case .paywallLoadStarted,
             .paywallLoadSuccess,
             .paywallLoadFailed,
             .paywallClosed,
             .productSelected,
             .restoreStarted,
             .restoreSuccess,
             .restoreNothingFound,
             .restoreUnavailable,
             .ruCheckoutCreated,
             .ruCheckoutOpenFailed,
             .ruCheckoutSafariReturned,
             .ruCheckoutConfirmed,
             .ruCheckoutTimedOut:
            nil
        }
    }
}
