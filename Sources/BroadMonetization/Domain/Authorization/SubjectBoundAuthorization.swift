import Foundation

public struct SubjectBoundAuthorization: Sendable {
    public let subject: EntitlementSubject

    let headerValue: String

    /// Creates a subject-bound RFC 6750 bearer credential.
    ///
    /// The initializer returns `nil` for malformed credentials instead of crashing the app.
    /// The token remains private to `BroadMonetization` and is never persisted or logged.
    public init?(
        subject: EntitlementSubject,
        bearerToken: String
    ) {
        guard !bearerToken.isEmpty,
              bearerToken.utf8.count <= 16 * 1024,
              Self.isValidBearerToken(bearerToken)
        else {
            return nil
        }

        self.subject = subject
        headerValue = "Bearer \(bearerToken)"
    }

    private static func isValidBearerToken(_ token: String) -> Bool {
        var reachedPadding = false
        for scalar in token.unicodeScalars {
            if scalar.value == 61 {
                reachedPadding = true
            } else if reachedPadding || !isAllowedBearerScalar(scalar) {
                return false
            }
        }
        return true
    }

    private static func isAllowedBearerScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 48 ... 57, 65 ... 90, 97 ... 122:
            true
        default:
            "-._~+/".unicodeScalars.contains(scalar)
        }
    }
}

/// App-wide revocation boundary shared by every authorization-dependent
/// composition for one host application.
///
/// A new identity bundle calls `begin(for:)`; this invalidates every binding
/// held by older in-flight tasks, including tasks that still retain an immutable
/// old authorization provider. Logout calls `invalidate()` even when no new
/// composition is created.
public final class SubjectAuthorizationSession: @unchecked Sendable {
    private let lock = NSLock()
    private var activeEpochID: UUID?
    private var activeSubject: EntitlementSubject?

    public init() {}

    public func begin(
        for subject: EntitlementSubject
    ) -> SubjectAuthorizationBinding {
        let epochID = UUID()
        lock.lock()
        activeEpochID = epochID
        activeSubject = subject
        lock.unlock()
        return SubjectAuthorizationBinding(
            session: self,
            subject: subject,
            epochID: epochID
        )
    }

    public func invalidate() {
        lock.lock()
        activeEpochID = nil
        activeSubject = nil
        lock.unlock()
    }

    fileprivate func isCurrent(
        subject: EntitlementSubject,
        epochID: UUID
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return activeSubject == subject && activeEpochID == epochID
    }
}

public struct SubjectAuthorizationBinding: Sendable {
    public let subject: EntitlementSubject

    private let session: SubjectAuthorizationSession
    private let epochID: UUID

    fileprivate init(
        session: SubjectAuthorizationSession,
        subject: EntitlementSubject,
        epochID: UUID
    ) {
        self.session = session
        self.subject = subject
        self.epochID = epochID
    }

    func isCurrent() -> Bool {
        session.isCurrent(subject: subject, epochID: epochID)
    }

    var cachePartition: String {
        "authorization-epoch-\(epochID.uuidString.lowercased())"
    }

    var cacheStoragePartition: String {
        "authorization-session"
    }
}

extension SubjectAuthorizationSession: CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable {
    public var description: String {
        "SubjectAuthorizationSession(<redacted>)"
    }

    public var debugDescription: String {
        description
    }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: ["authorizationSession": "<redacted>"],
            displayStyle: .class
        )
    }
}

extension SubjectAuthorizationBinding: CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable {
    public var description: String {
        "SubjectAuthorizationBinding(<redacted>)"
    }

    public var debugDescription: String {
        description
    }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: ["authorizationBinding": "<redacted>"],
            displayStyle: .struct
        )
    }
}

/// A transient identity for one exact subject-bound credential.
///
/// RU billing carries this proof across suspension points so a response created
/// for an old login session cannot be accepted after logout, account switch or
/// credential rotation. Its private value remains transient, redacted and
/// module-internal; it is never persisted or logged.
struct SubjectAuthorizationProof: Sendable {
    let subject: EntitlementSubject
    private let binding: SubjectAuthorizationBinding
    private let headerValue: String

    init(
        authorization: SubjectBoundAuthorization,
        binding: SubjectAuthorizationBinding
    ) {
        precondition(
            authorization.subject == binding.subject,
            "Authorization proof subject must match its session binding"
        )
        subject = authorization.subject
        self.binding = binding
        headerValue = authorization.headerValue
    }

    func matches(_ authorization: SubjectBoundAuthorization) -> Bool {
        binding.isCurrent()
            && subject == authorization.subject
            && headerValue == authorization.headerValue
    }
}

extension SubjectAuthorizationProof: CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "SubjectAuthorizationProof(<redacted>)"
    }

    var debugDescription: String {
        description
    }

    var customMirror: Mirror {
        Mirror(
            self,
            children: ["credential": "<redacted>"],
            displayStyle: .struct
        )
    }
}

/// Supplies a short-lived authorization credential owned by the host application.
/// The platform never persists or logs the credential.
/// The provider must return a credential for the exact requested subject. Every
/// identity bundle also uses a binding from one shared `SubjectAuthorizationSession`;
/// login/account switch begins a new binding and logout invalidates the session.
public protocol SubjectAuthorizationProviderProtocol: Sendable {
    func authorization(
        for subject: EntitlementSubject
    ) async -> SubjectBoundAuthorization?
}

extension SubjectAuthorizationProviderProtocol {
    func stillOwns(_ proof: SubjectAuthorizationProof) async -> Bool {
        guard proof.isSessionCurrent,
              !Task.isCancelled,
              let current = await authorization(for: proof.subject)
        else {
            return false
        }
        return proof.matches(current)
    }
}

extension SubjectAuthorizationProof {
    var isSessionCurrent: Bool {
        binding.isCurrent()
    }
}

extension SubjectBoundAuthorization: CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable {
    public var description: String {
        "SubjectBoundAuthorization(<redacted>)"
    }

    public var debugDescription: String {
        description
    }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: ["credential": "<redacted>"],
            displayStyle: .struct
        )
    }
}
