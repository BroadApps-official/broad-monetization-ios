import BroadCore
import BroadMonetization

/// Compile-only example: the backend adapter explicitly classifies finality.
/// No SDK activation, network request or financial operation is performed.
enum TokenFulfillmentWiringExample {
    enum BackendReply {
        case credited(TokenBalanceSnapshot)
        case alreadyCredited(TokenBalanceSnapshot)
        case processing
        case temporarilyUnavailable(AppError)
        case unclassifiedFailure(AppError)
        case definitiveRefusal(AppError)
    }

    static func outcome(for reply: BackendReply) -> TokenFulfillmentOutcome {
        switch reply {
        case let .credited(balance): .credited(balance)
        case let .alreadyCredited(balance): .alreadyCredited(balance)
        case .processing: .pending
        case let .temporarilyUnavailable(error): .unavailable(error)
        case let .unclassifiedFailure(error): .failed(error)
        case let .definitiveRefusal(error): .rejected(error)
        }
    }
}
