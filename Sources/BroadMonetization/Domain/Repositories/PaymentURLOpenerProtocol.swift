import Foundation

public protocol PaymentURLOpenerProtocol: Sendable {
    @MainActor
    func open(_ url: URL) async -> Bool
}
