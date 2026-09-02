/// Reads the current provider profile identifier for diagnostics only, such as a
/// support-email "profile ID" field.
///
/// The identifier is read from the existing provider profile; an implementation
/// must never create a new profile just to fill a diagnostics field. `nil` when
/// the provider has no profile yet or the lookup fails, so a host shows its own
/// "unavailable" placeholder instead of a fabricated value.
public protocol ProfileIdentityProviderProtocol: Sendable {
    func currentProfileID() async -> String?
}
