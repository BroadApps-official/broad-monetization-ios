import Foundation
import StoreKit

public enum StoreKitStorefrontClientResult: Equatable, Sendable {
    case available(Storefront)
    case unavailable
}

public protocol StoreKitStorefrontClientProtocol: Sendable {
    func loadCurrentStorefront() async -> StoreKitStorefrontClientResult
}

/// Reads the storefront tied to the App Store account as informational data.
public struct StoreKitCurrentStorefrontClient: StoreKitStorefrontClientProtocol {
    public init() {}

    public func loadCurrentStorefront() async -> StoreKitStorefrontClientResult {
        guard !Task.isCancelled,
              let storefront = await StoreKit.Storefront.current
        else {
            return .unavailable
        }

        let countryCode = storefront.countryCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard (2 ... 3).contains(countryCode.count),
              countryCode.allSatisfy({ $0.isASCII && $0.isLetter })
        else {
            return .unavailable
        }

        return .available(
            Storefront(
                identifier: storefront.id,
                countryCode: countryCode
            )
        )
    }
}
