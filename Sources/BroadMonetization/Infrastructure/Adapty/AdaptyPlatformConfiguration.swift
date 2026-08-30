import Foundation

public struct AdaptyCustomerIdentity: Sendable {
    public let subject: EntitlementSubject

    let customerUserID: String
    let appAccountToken: UUID?

    public init?(
        subject: EntitlementSubject,
        customerUserID: String,
        appAccountToken: UUID? = nil
    ) {
        let trimmedIdentifier = customerUserID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedIdentifier.isEmpty,
              trimmedIdentifier == customerUserID,
              customerUserID.utf8.count <= 1024,
              !customerUserID.contains("\r"),
              !customerUserID.contains("\n")
        else {
            return nil
        }

        self.subject = subject
        self.customerUserID = customerUserID
        self.appAccountToken = appAccountToken
    }
}

public protocol AdaptyIdentityProviderProtocol: Sendable {
    func identity(
        for subject: EntitlementSubject
    ) async -> AdaptyCustomerIdentity?
}

/// Standard identity provider for apps that let Adapty manage an anonymous
/// customer. Signed-in apps can inject their own provider instead.
public struct AdaptyAnonymousIdentityProvider: AdaptyIdentityProviderProtocol {
    public init() {}

    public func identity(
        for _: EntitlementSubject
    ) async -> AdaptyCustomerIdentity? {
        nil
    }
}

public struct AdaptyPlatformConfiguration: Sendable {
    public let subject: EntitlementSubject
    public let accessLevelID: String
    public let observerMode: Bool
    public let idfaCollectionDisabled: Bool
    public let ipAddressCollectionDisabled: Bool
    public let paywallLoadTimeout: TimeInterval
    public let fallbackFileURL: URL?

    let apiKey: String

    /// Basic Adapty setup. Loading and presenting paywalls needs the public SDK
    /// key and placement registry; an Adapty access level is not required.
    public init?(
        apiKey: String,
        subject: EntitlementSubject = .anonymous,
        observerMode: Bool = false,
        idfaCollectionDisabled: Bool = true,
        ipAddressCollectionDisabled: Bool = true,
        paywallLoadTimeout: TimeInterval = 12,
        fallbackFileURL: URL? = nil
    ) {
        guard let validated = Self.validatedInput(
            apiKey: apiKey,
            accessLevelID: "",
            paywallLoadTimeout: paywallLoadTimeout,
            fallbackFileURL: fallbackFileURL,
            requiresAccessLevel: false
        ) else {
            return nil
        }

        self.apiKey = validated.apiKey
        accessLevelID = validated.accessLevelID
        self.subject = subject
        self.observerMode = observerMode
        self.idfaCollectionDisabled = idfaCollectionDisabled
        self.ipAddressCollectionDisabled = ipAddressCollectionDisabled
        self.paywallLoadTimeout = paywallLoadTimeout
        self.fallbackFileURL = validated.fallbackFileURL
    }

    /// Advanced compatibility setup for hosts that expose an Adapty access
    /// level to their own entitlement adapter. Ordinary paywall loading does
    /// not need this value.
    public init?(
        apiKey: String,
        accessLevelID: String,
        subject: EntitlementSubject,
        observerMode: Bool = false,
        idfaCollectionDisabled: Bool = true,
        ipAddressCollectionDisabled: Bool = true,
        paywallLoadTimeout: TimeInterval = 12,
        fallbackFileURL: URL? = nil
    ) {
        guard let validated = Self.validatedInput(
            apiKey: apiKey,
            accessLevelID: accessLevelID,
            paywallLoadTimeout: paywallLoadTimeout,
            fallbackFileURL: fallbackFileURL,
            requiresAccessLevel: true
        ) else {
            return nil
        }

        self.apiKey = validated.apiKey
        self.accessLevelID = validated.accessLevelID
        self.subject = subject
        self.observerMode = observerMode
        self.idfaCollectionDisabled = idfaCollectionDisabled
        self.ipAddressCollectionDisabled = ipAddressCollectionDisabled
        self.paywallLoadTimeout = paywallLoadTimeout
        self.fallbackFileURL = validated.fallbackFileURL
    }
}

private extension AdaptyPlatformConfiguration {
    struct ValidatedInput {
        let apiKey: String
        let accessLevelID: String
        let fallbackFileURL: URL?
    }

    static func validatedInput(
        apiKey: String,
        accessLevelID: String,
        paywallLoadTimeout: TimeInterval,
        fallbackFileURL: URL?,
        requiresAccessLevel: Bool
    ) -> ValidatedInput? {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAccessLevel = accessLevelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedFallbackURL = fallbackFileURL?.standardizedFileURL
        let hasValidFallbackURL = normalizedFallbackURL.map {
            $0.isFileURL && $0.pathExtension.lowercased() == "json"
        } ?? true
        guard !trimmedKey.isEmpty,
              trimmedKey == apiKey,
              apiKey.utf8.count <= 16 * 1024,
              !requiresAccessLevel || !trimmedAccessLevel.isEmpty,
              trimmedAccessLevel == accessLevelID,
              paywallLoadTimeout.isFinite,
              (1 ... 60).contains(paywallLoadTimeout),
              hasValidFallbackURL
        else {
            return nil
        }

        return ValidatedInput(
            apiKey: apiKey,
            accessLevelID: accessLevelID,
            fallbackFileURL: normalizedFallbackURL
        )
    }
}

extension AdaptyCustomerIdentity: CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable {
    public var description: String {
        "AdaptyCustomerIdentity(<redacted>)"
    }

    public var debugDescription: String {
        description
    }

    public var customMirror: Mirror {
        Mirror(self, children: ["identity": "<redacted>"], displayStyle: .struct)
    }
}

extension AdaptyPlatformConfiguration: CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable {
    public var description: String {
        let fallback = fallbackFileURL == nil ? "not-configured" : "configured"
        let accessLevel = accessLevelID.isEmpty ? "not-configured" : "configured"
        return "AdaptyPlatformConfiguration(apiKey: <redacted>, accessLevel: \(accessLevel), fallback: \(fallback))"
    }

    public var debugDescription: String {
        description
    }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "apiKey": "<redacted>",
                "fallback": fallbackFileURL == nil ? "not-configured" : "configured"
            ],
            displayStyle: .struct
        )
    }
}
