import BroadCore

/// A backend-authoritative terminal state in which an RU checkout can no
/// longer settle successfully.
public enum RUCheckoutTerminalStatus: String, Codable, Equatable, Sendable {
    case failed
    case cancelled
    case expired
}

/// The minimum correlation data required to terminate the exact pending
/// checkout. The client itself is composed for one authenticated subject.
public struct RUPendingCheckoutTerminationRequest: Equatable, Sendable {
    public let checkoutSessionID: CheckoutSessionID
    public let attemptID: MonetizationAttemptID
    public let productID: RUCatalogProductID
    public let checkoutMethod: CheckoutMethod

    public init(
        checkoutSessionID: CheckoutSessionID,
        attemptID: MonetizationAttemptID,
        productID: RUCatalogProductID,
        checkoutMethod: CheckoutMethod
    ) {
        precondition(
            checkoutMethod == .sbp || checkoutMethod == .card,
            "Pending RU checkout termination supports only SBP or card"
        )
        self.checkoutSessionID = checkoutSessionID
        self.attemptID = attemptID
        self.productID = productID
        self.checkoutMethod = checkoutMethod
    }
}

public enum RUPendingCheckoutTerminationResult: Equatable, Sendable {
    /// The backend guarantees that this checkout can no longer settle.
    case terminated(RUCheckoutTerminalStatus)
    case pending
    case unavailable(AppError)
}

/// Subject-bound backend authority for an abandoned RU checkout.
///
/// Implementations must perform a fresh authenticated request and return
/// ``RUPendingCheckoutTerminationResult/terminated(_:)`` only after the backend
/// atomically cancels the checkout or proves it is already terminal. Page
/// dismissal, device time and a local expiration date are not terminal proof.
/// Repeated calls for the same request must be idempotent.
public protocol RUCheckoutTerminationClientProtocol: Sendable {
    func terminatePendingCheckout(
        _ request: RUPendingCheckoutTerminationRequest
    ) async -> RUPendingCheckoutTerminationResult
}

public enum RUPendingCheckoutTerminationOutcome: Equatable, Sendable {
    case noPendingCheckout
    case terminated(RUCheckoutTerminalStatus)
    case pending
    case unavailable(AppError)
}
