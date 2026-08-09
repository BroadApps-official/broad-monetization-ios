/// Serializes analytics delivery without allowing a slow or stuck host
/// destination to delay paywalls, purchases, entitlement reconciliation or
/// payment-return handling.
public actor NonBlockingMonetizationAnalytics: MonetizationAnalyticsProtocol {
    private let destination: any MonetizationAnalyticsProtocol
    private let retainedEventLimit: Int

    private var events: [MonetizationAnalyticsEvent] = []
    private var isDraining = false

    public init(
        destination: any MonetizationAnalyticsProtocol,
        retainedEventLimit: Int = 2048
    ) {
        precondition(
            retainedEventLimit > 0,
            "Analytics retained event limit must be positive"
        )
        self.destination = destination
        self.retainedEventLimit = retainedEventLimit
    }

    /// Returns the existing delivery queue when one was already supplied, so a
    /// composition can share ordering across all monetization use cases.
    public nonisolated static func wrapping(
        _ analytics: any MonetizationAnalyticsProtocol
    ) -> any MonetizationAnalyticsProtocol {
        if analytics is NonBlockingMonetizationAnalytics {
            return analytics
        }
        return NonBlockingMonetizationAnalytics(destination: analytics)
    }

    /// Enqueues and returns. Destination work is deliberately performed by the
    /// drain task, never by the caller's financial or navigation operation.
    public func track(
        _ event: MonetizationAnalyticsEvent
    ) async {
        if events.count == retainedEventLimit {
            events.removeFirst()
        }
        events.append(event)

        guard !isDraining else {
            return
        }

        isDraining = true
        Task { [weak self] in
            await self?.drain()
        }
    }

    private func drain() async {
        while !events.isEmpty {
            let event = events.removeFirst()
            await destination.track(event)
        }
        isDraining = false
    }
}
