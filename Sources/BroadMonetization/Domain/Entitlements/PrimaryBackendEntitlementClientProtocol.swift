import Foundation

public struct PrimaryBackendEntitlementSnapshot: Equatable, Sendable {
    public let subject: EntitlementSubject
    public let isActive: Bool
    public let expiresAt: Date?
    public let isLifetime: Bool

    public init(
        subject: EntitlementSubject,
        isActive: Bool,
        expiresAt: Date?,
        isLifetime: Bool = false
    ) {
        self.subject = subject
        self.isActive = isActive
        self.expiresAt = expiresAt
        self.isLifetime = isLifetime
    }
}

/// A current response whose identity and transport provenance were validated by the client.
public enum PrimaryBackendEntitlementClientResult: Equatable, Sendable {
    case serverValidated(PrimaryBackendEntitlementSnapshot)
    case unresolved
}

public protocol PrimaryBackendEntitlementClientProtocol: Sendable {
    func loadEntitlement(
        for subject: EntitlementSubject
    ) async -> PrimaryBackendEntitlementClientResult
}
