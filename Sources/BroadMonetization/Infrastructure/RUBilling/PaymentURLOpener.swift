import Foundation
import UIKit

public protocol PaymentURLOpenerProtocol: Sendable {
    @MainActor
    func open(_ url: URL) async -> Bool
}

public struct UIApplicationPaymentURLOpener: PaymentURLOpenerProtocol {
    public init() {}

    @MainActor
    public func open(_ url: URL) async -> Bool {
        guard url.scheme?.lowercased() == "https",
              url.host?.isEmpty == false,
              url.user == nil,
              url.password == nil
        else {
            return false
        }

        return await withCheckedContinuation { continuation in
            UIApplication.shared.open(url, options: [:]) { didOpen in
                continuation.resume(returning: didOpen)
            }
        }
    }
}
