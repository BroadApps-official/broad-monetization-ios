import BroadCore
import Foundation

public actor VersionedEntitlementCache: EntitlementCacheProtocol {
    public static let defaultSchemaIdentifier = "com.broadapps.platform.entitlement-source"
    public static let currentVersion = 1
    public static let defaultMaximumRetention: TimeInterval = 31_536_000

    private let repository: any CacheRepositoryProtocol
    private let schemaIdentifier: String
    private let version: Int
    private let maximumRetention: TimeInterval
    private let clock: CacheClock

    public init(
        repository: any CacheRepositoryProtocol,
        schemaIdentifier: String = VersionedEntitlementCache.defaultSchemaIdentifier,
        version: Int = VersionedEntitlementCache.currentVersion,
        maximumRetention: TimeInterval = VersionedEntitlementCache.defaultMaximumRetention,
        clock: CacheClock = .system
    ) {
        precondition(
            !schemaIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            "Entitlement cache schema identifier must not be empty"
        )
        precondition(version > 0, "Entitlement cache version must be greater than zero")
        precondition(
            maximumRetention.isFinite && maximumRetention > 0,
            "Entitlement cache retention must be finite and greater than zero"
        )

        self.repository = repository
        self.schemaIdentifier = schemaIdentifier
        self.version = version
        self.maximumRetention = maximumRetention
        self.clock = clock
    }

    public func read(
        for scope: EntitlementCacheScope
    ) async throws -> EntitlementSourceAssertion? {
        let key = key(for: scope)
        let result = try await repository.read(key)
        let record: EntitlementSourceRecordV1

        switch result {
        case let .fresh(envelope):
            record = envelope.value
        case let .stale(envelope):
            let now = clock.now()
            guard now >= envelope.savedAt, now < envelope.expiresAt else {
                return nil
            }
            record = envelope.value
        case .missing:
            return nil
        }

        guard let assertion = record.assertion(for: scope) else {
            return nil
        }

        return assertion
    }

    public func write(
        _ assertion: EntitlementSourceAssertion,
        for scope: EntitlementCacheScope
    ) async throws {
        precondition(
            assertion.source == scope.source,
            "Entitlement assertion source must match its cache scope"
        )

        try await repository.write(
            EntitlementSourceRecordV1(
                assertion: assertion,
                scope: scope
            ),
            for: key(for: scope)
        )
    }

    private func key(
        for scope: EntitlementCacheScope
    ) -> CacheKey<EntitlementSourceRecordV1> {
        let subject = scope.subject.cacheKeyComponent
        let source = scope.source.rawValue
        let sharedName = "\(lengthPrefixed(subject))#\(lengthPrefixed(source))"
        let name = scope.storagePartition.map {
            "\(sharedName)#\(lengthPrefixed($0))"
        } ?? sharedName

        return CacheKey(
            name: name,
            schemaIdentifier: schemaIdentifier,
            version: version,
            policy: CachePolicy(timeToLive: maximumRetention)
        )
    }

    private func lengthPrefixed(_ value: String) -> String {
        "\(value.utf8.count)#\(value)"
    }
}

private struct EntitlementSourceRecordV1: Codable, Sendable {
    let source: String
    let subjectFingerprint: String
    let partition: String?
    let assertion: AssertionValue
    let validity: ValidityValue?
    let entitlementExpiresAt: Date?
    let validatedAt: Date
    let freshUntil: Date
    let activeGraceUntil: Date

    init(
        assertion: EntitlementSourceAssertion,
        scope: EntitlementCacheScope
    ) {
        source = assertion.source.rawValue
        subjectFingerprint = scope.subject.cacheKeyComponent
        partition = scope.partition
        validatedAt = assertion.validatedAt
        freshUntil = assertion.freshUntil
        activeGraceUntil = assertion.activeGraceUntil

        switch assertion.state {
        case let .active(activeValidity):
            self.assertion = .active
            switch activeValidity {
            case let .expires(expirationDate):
                validity = .expires
                entitlementExpiresAt = expirationDate
            case .lifetime:
                validity = .lifetime
                entitlementExpiresAt = nil
            case .unspecified:
                validity = .unspecified
                entitlementExpiresAt = nil
            }
        case .inactive:
            self.assertion = .inactive
            validity = nil
            entitlementExpiresAt = nil
        }
    }

    func assertion(
        for scope: EntitlementCacheScope
    ) -> EntitlementSourceAssertion? {
        guard
            source == scope.source.rawValue,
            subjectFingerprint == scope.subject.cacheKeyComponent,
            partition == scope.partition,
            hasValidDates
        else {
            return nil
        }

        let state: ResolvedEntitlementState
        switch assertion {
        case .active:
            guard let activeValidity else {
                return nil
            }
            state = .active(activeValidity)
        case .inactive:
            guard validity == nil, entitlementExpiresAt == nil else {
                return nil
            }
            state = .inactive
        }

        return EntitlementSourceAssertion(
            source: scope.source,
            state: state,
            validatedAt: validatedAt,
            freshUntil: freshUntil,
            activeGraceUntil: activeGraceUntil
        )
    }

    private var activeValidity: EntitlementActiveValidity? {
        switch validity {
        case .expires:
            guard
                let entitlementExpiresAt,
                entitlementExpiresAt.timeIntervalSinceReferenceDate.isFinite
            else {
                return nil
            }
            return .expires(at: entitlementExpiresAt)
        case .lifetime:
            return entitlementExpiresAt == nil ? .lifetime : nil
        case .unspecified:
            return entitlementExpiresAt == nil ? .unspecified : nil
        case nil:
            return nil
        }
    }

    private var hasValidDates: Bool {
        let timestamps = [
            validatedAt.timeIntervalSinceReferenceDate,
            freshUntil.timeIntervalSinceReferenceDate,
            activeGraceUntil.timeIntervalSinceReferenceDate
        ]

        return timestamps.allSatisfy(\.isFinite)
            && freshUntil >= validatedAt
            && activeGraceUntil >= freshUntil
    }
}

private extension EntitlementSourceRecordV1 {
    enum AssertionValue: String, Codable, Sendable {
        case active
        case inactive
    }

    enum ValidityValue: String, Codable, Sendable {
        case expires
        case lifetime
        case unspecified
    }
}
