import BroadCore

public struct MonetizationFlowErrors: Sendable {
    public let stalePaywallLoad: AppError
    public let purchaseInProgress: AppError
    public let restoreVerificationUnavailable: AppError

    public init(
        stalePaywallLoad: AppError,
        purchaseInProgress: AppError,
        restoreVerificationUnavailable: AppError
    ) {
        self.stalePaywallLoad = stalePaywallLoad
        self.purchaseInProgress = purchaseInProgress
        self.restoreVerificationUnavailable = restoreVerificationUnavailable
    }
}
