import Adapty
import Foundation

/// Reads the current Adapty profile identifier for diagnostics, without ever
/// creating a new profile. Returns `nil` when the SDK is not activated yet or the
/// profile lookup fails, so a host falls back to its own placeholder.
public struct AdaptySDKProfileIdentityProvider: ProfileIdentityProviderProtocol {
    public init() {}

    public func currentProfileID() async -> String? {
        await (try? Adapty.getProfile())?.profileId
    }
}
