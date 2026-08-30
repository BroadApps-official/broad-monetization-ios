import Foundation

/// Reads the region selected on the iPhone. Language is presentation metadata
/// and never enables RU billing.
public struct SystemRUBillingDeviceContextProvider:
    RUBillingDeviceContextProviderProtocol {
    public init() {}

    public func currentContext() -> RUBillingDeviceContext {
        RUBillingDeviceContext(regionCode: Locale.current.region?.identifier)
    }
}
