import Foundation
import StoreKit

enum ApplePurchaseErrorDisposition: Equatable {
    case cancelled
    case definitivelyNotPurchased
    case outcomeUnknown
}

/// Used only for errors raised by StoreKit's purchase call. A failed SDK
/// validation after a verified transaction must never enter this classifier.
enum ApplePurchaseErrorClassifier {
    static func classify(_ error: any Error) -> ApplePurchaseErrorDisposition {
        classify(error, depth: 0)
    }

    private static func classify(
        _ error: any Error,
        depth: Int
    ) -> ApplePurchaseErrorDisposition {
        guard depth < 5 else { return .outcomeUnknown }

        if let storeKitError = error as? StoreKitError {
            return classifyStoreKit(storeKitError, depth: depth)
        }

        let nsError = error as NSError
        if nsError.domain == SKErrorDomain,
           let code = SKError.Code(rawValue: nsError.code) {
            return classifySKError(code)
        }

        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? any Error {
            return classify(underlying, depth: depth + 1)
        }
        return .outcomeUnknown
    }

    private static func classifyStoreKit(
        _ error: StoreKitError,
        depth: Int
    ) -> ApplePurchaseErrorDisposition {
        switch error {
        case .userCancelled:
            .cancelled
        case .notAvailableInStorefront, .notEntitled, .unsupported:
            .definitivelyNotPurchased
        case let .systemError(underlying):
            classify(underlying, depth: depth + 1)
        default:
            .outcomeUnknown
        }
    }

    private static func classifySKError(
        _ code: SKError.Code
    ) -> ApplePurchaseErrorDisposition {
        switch code {
        case .paymentCancelled, .overlayCancelled:
            .cancelled
        case .clientInvalid, .paymentInvalid, .paymentNotAllowed,
             .storeProductNotAvailable, .invalidOfferIdentifier,
             .invalidSignature, .missingOfferParams, .invalidOfferPrice,
             .ineligibleForOffer, .unauthorizedRequestData:
            .definitivelyNotPurchased
        default:
            .outcomeUnknown
        }
    }
}
