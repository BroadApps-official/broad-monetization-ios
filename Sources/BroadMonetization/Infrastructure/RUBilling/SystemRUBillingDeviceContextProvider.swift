import Foundation

/// Mirrors the production rule used by 5115: the active system language and
/// the region selected on the iPhone are independent positive signals.
public struct SystemRUBillingDeviceContextProvider:
    RUBillingDeviceContextProviderProtocol {
    public init() {}

    public func currentContext() -> RUBillingDeviceContext {
        RUBillingDeviceContext(
            regionCode: Locale.current.region?.identifier,
            primaryLanguageIdentifier: Locale.preferredLanguages.first
        )
    }
}
