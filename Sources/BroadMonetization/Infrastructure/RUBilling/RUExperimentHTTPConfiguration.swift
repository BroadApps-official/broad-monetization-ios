import Foundation

/// Endpoint paths are enabled only by explicitly creating an experiment
/// tracker. The existing RU checkout configuration and credentials are reused.
public struct RUExperimentHTTPConfiguration: Sendable {
    public static let broadApps = RUExperimentHTTPConfiguration(
        assign: RUBillingEndpointPath(rawValue: "/v1/billing/cloudpayments/experiments/assign"),
        paywallShown: RUBillingEndpointPath(rawValue: "/v1/billing/cloudpayments/experiments/paywall-shown")
    )

    public let assign: RUBillingEndpointPath
    public let paywallShown: RUBillingEndpointPath
    public let requestTimeout: TimeInterval

    public init(
        assign: RUBillingEndpointPath,
        paywallShown: RUBillingEndpointPath,
        requestTimeout: TimeInterval = 10
    ) {
        precondition(
            requestTimeout.isFinite && requestTimeout > 0,
            "RU experiment timeout must be finite and positive"
        )
        self.assign = assign
        self.paywallShown = paywallShown
        self.requestTimeout = requestTimeout
    }
}
