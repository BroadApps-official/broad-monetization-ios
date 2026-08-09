public struct CompositeMonetizationAnalytics: MonetizationAnalyticsProtocol {
    private let destinations: [any MonetizationAnalyticsProtocol]

    public init(
        destinations: [any MonetizationAnalyticsProtocol]
    ) {
        self.destinations = destinations
    }

    public func track(
        _ event: MonetizationAnalyticsEvent
    ) async {
        for destination in destinations {
            guard !Task.isCancelled else {
                return
            }
            await destination.track(event)
        }
    }
}
