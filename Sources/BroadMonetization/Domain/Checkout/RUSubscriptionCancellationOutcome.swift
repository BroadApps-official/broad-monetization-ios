import BroadCore
import Foundation

public enum RUSubscriptionCancellationOutcome: Equatable, Sendable {
    case cancelled(effectiveUntil: Date?)
    case alreadyInactive
    case unavailable(AppError)
    case failed(AppError)
}
