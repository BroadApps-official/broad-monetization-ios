public struct NoOpMonetizationAnalytics: MonetizationAnalyticsProtocol {
    public init() {}

    public func track(
        _ event: MonetizationAnalyticsEvent
    ) async {}
}
