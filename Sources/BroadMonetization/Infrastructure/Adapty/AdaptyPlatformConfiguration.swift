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

public struct AdaptyPlatformConfiguration: Sendable {
    public let subject: EntitlementSubject
    public let accessLevelID: String
    public let observerMode: Bool
    public let idfaCollectionDisabled: Bool
    public let ipAddressCollectionDisabled: Bool
    public let paywallLoadTimeout: TimeInterval

    let apiKey: String

    public init?(
        apiKey: String,
        accessLevelID: String,
        subject: EntitlementSubject,
        observerMode: Bool = false,
        idfaCollectionDisabled: Bool = true,
        ipAddressCollectionDisabled: Bool = true,
        paywallLoadTimeout: TimeInterval = 12
    ) {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAccessLevel = accessLevelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty,
              trimmedKey == apiKey,
              apiKey.utf8.count <= 16 * 1024,
              !trimmedAccessLevel.isEmpty,
              trimmedAccessLevel == accessLevelID,
              paywallLoadTimeout.isFinite,
              (1 ... 60).contains(paywallLoadTimeout)
        else {
            return nil
        }

        self.apiKey = apiKey
        self.accessLevelID = accessLevelID
        self.subject = subject
        self.observerMode = observerMode
        self.idfaCollectionDisabled = idfaCollectionDisabled
        self.ipAddressCollectionDisabled = ipAddressCollectionDisabled
        self.paywallLoadTimeout = paywallLoadTimeout
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
        "AdaptyPlatformConfiguration(apiKey: <redacted>, accessLevel: configured)"
    }

    public var debugDescription: String {
        description
    }

    public var customMirror: Mirror {
        Mirror(self, children: ["apiKey": "<redacted>"], displayStyle: .struct)
    }
}
