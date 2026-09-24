import Foundation
import StoreKit

@main
enum ApplePurchaseErrorProbe {
    static func main() {
        expect(StoreKitError.userCancelled, .cancelled)
        expect(SKError(.paymentCancelled), .cancelled)
        expect(SKError(.overlayCancelled), .cancelled)
        expect(SKError(.paymentNotAllowed), .definitivelyNotPurchased)
        expect(StoreKitError.notAvailableInStorefront, .definitivelyNotPurchased)
        expect(StoreKitError.notEntitled, .definitivelyNotPurchased)
        if #available(macOS 15.4, *) {
            expect(StoreKitError.unsupported, .definitivelyNotPurchased)
        }
        expect(
            NSError(
                domain: "fixture.sdk.purchase",
                code: 1006,
                userInfo: [NSUnderlyingErrorKey: SKError(.paymentCancelled)]
            ),
            .cancelled
        )
        expect(
            StoreKitError.systemError(SKError(.paymentInvalid)),
            .definitivelyNotPurchased
        )
        expect(
            StoreKitError.networkError(URLError(.notConnectedToInternet)),
            .outcomeUnknown
        )
        expect(SKError(.unknown), .outcomeUnknown)
        expect(
            NSError(domain: "fixture.sdk.validation", code: 1006),
            .outcomeUnknown
        )
        print(
            "Apple purchase error classification passed: terminal and cancelled StoreKit errors permit retry; ambiguous errors stay blocked."
        )
    }

    private static func expect(
        _ error: any Error,
        _ expected: ApplePurchaseErrorDisposition
    ) {
        let actual = ApplePurchaseErrorClassifier.classify(error)
        guard actual == expected else {
            fatalError("Apple purchase error classification mismatch: \(error): \(actual) != \(expected)")
        }
    }
}
