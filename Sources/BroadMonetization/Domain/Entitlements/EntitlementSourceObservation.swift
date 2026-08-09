public struct EntitlementSourceObservation: Equatable, Sendable {
    public let source: EntitlementSource
    public let freshnessPolicy: EntitlementFreshnessPolicy
    public let assertion: EntitlementSourceAssertion?
    public let isFromCurrentRefresh: Bool

    public init(
        source: EntitlementSource,
        freshnessPolicy: EntitlementFreshnessPolicy,
        assertion: EntitlementSourceAssertion?,
        isFromCurrentRefresh: Bool
    ) {
        precondition(
            assertion == nil || assertion?.source == source,
            "Entitlement assertion source must match its observation"
        )

        self.source = source
        self.freshnessPolicy = freshnessPolicy
        self.assertion = assertion
        self.isFromCurrentRefresh = isFromCurrentRefresh
    }
}
