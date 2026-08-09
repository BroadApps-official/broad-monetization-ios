import Adapty
import Foundation

public protocol AdaptyEntitlementProfileClientProtocol: Sendable {
    /// `serverValidated` is reserved for a profile freshly validated by a remote authority
    /// for this exact request and subject. Ordinary Adapty SDK cache is `unqualified`.
    func loadProfile(
        for subject: EntitlementSubject
    ) async -> AdaptyEntitlementProfileResult
}

public enum AdaptyEntitlementProfileResult: Equatable, Sendable {
    case serverValidated(AdaptyEntitlementProfileSnapshot)
    case unqualified(AdaptyEntitlementProfileSnapshot)
    case unresolved
}

public struct AdaptyEntitlementProfileSnapshot: Equatable, Sendable {
    public let subject: EntitlementSubject
    public let accessLevels: [String: AdaptyEntitlementAccessLevelSnapshot]

    public init(
        subject: EntitlementSubject,
        accessLevels: [String: AdaptyEntitlementAccessLevelSnapshot]
    ) {
        self.subject = subject
        self.accessLevels = accessLevels
    }
}

public struct AdaptyEntitlementAccessLevelSnapshot: Equatable, Sendable {
    public let identifier: String
    public let isActive: Bool
    public let expiresAt: Date?
    public let isLifetime: Bool
    public let isInGracePeriod: Bool
    public let startsAt: Date?
    public let isRefund: Bool

    public init(
        identifier: String,
        isActive: Bool,
        expiresAt: Date?,
        isLifetime: Bool,
        isInGracePeriod: Bool,
        startsAt: Date?,
        isRefund: Bool
    ) {
        self.identifier = identifier
        self.isActive = isActive
        self.expiresAt = expiresAt
        self.isLifetime = isLifetime
        self.isInGracePeriod = isInGracePeriod
        self.startsAt = startsAt
        self.isRefund = isRefund
    }
}

/// Calls the public Adapty 3 profile API. Adapty may silently return its local cache,
/// so a successful result intentionally remains `unqualified`.
public struct AdaptySDKEntitlementProfileClient: AdaptyEntitlementProfileClientProtocol {
    private struct SDKBinding: Sendable {
        let configuration: AdaptyPlatformConfiguration
        let identityProvider: any AdaptyIdentityProviderProtocol
        let context: AdaptyRepositoryContext
    }

    private let subject: EntitlementSubject
    private let binding: SDKBinding?

    public init(
        configuration: AdaptyPlatformConfiguration,
        identityProvider: any AdaptyIdentityProviderProtocol,
        context: AdaptyRepositoryContext
    ) {
        subject = configuration.subject
        binding = SDKBinding(
            configuration: configuration,
            identityProvider: identityProvider,
            context: context
        )
    }

    /// Kept for source compatibility. A subject alone cannot prove ownership of
    /// the process-global SDK identity, so this legacy composition fails closed.
    @available(*, deprecated, message: "Use init(configuration:identityProvider:context:)")
    public init(subject: EntitlementSubject) {
        self.subject = subject
        binding = nil
    }

    public func loadProfile(
        for subject: EntitlementSubject
    ) async -> AdaptyEntitlementProfileResult {
        guard subject == self.subject,
              let binding,
              !Task.isCancelled
        else {
            return .unresolved
        }

        return await AdaptySDKActivationGate.shared.perform(
            configuration: binding.configuration,
            identityProvider: binding.identityProvider,
            compositionID: binding.context.sdkCompositionID,
            operation: {
                await Self.loadUnqualifiedProfile(for: subject)
            }
        ) ?? .unresolved
    }
}

private extension AdaptySDKEntitlementProfileClient {
    static func loadUnqualifiedProfile(
        for subject: EntitlementSubject
    ) async -> AdaptyEntitlementProfileResult {
        do {
            let profile = try await Adapty.getProfile()

            guard !Task.isCancelled else {
                return .unresolved
            }

            let accessLevels = profile.accessLevels.mapValues { accessLevel in
                AdaptyEntitlementAccessLevelSnapshot(
                    identifier: accessLevel.id,
                    isActive: accessLevel.isActive,
                    expiresAt: accessLevel.expiresAt,
                    isLifetime: accessLevel.isLifetime,
                    isInGracePeriod: accessLevel.isInGracePeriod,
                    startsAt: accessLevel.startsAt,
                    isRefund: accessLevel.isRefund
                )
            }
            return .unqualified(
                AdaptyEntitlementProfileSnapshot(
                    subject: subject,
                    accessLevels: accessLevels
                )
            )
        } catch {
            return .unresolved
        }
    }
}
