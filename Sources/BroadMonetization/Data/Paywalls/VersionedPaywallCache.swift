import BroadCore
import Foundation

/// Persistent, subject-scoped cache for provider-neutral paywall payloads.
///
/// The cache can keep the last catalog visible during a temporary network
/// failure. It never proves premium access and never bypasses the exact product
/// rehydration checks performed before purchase.
public actor VersionedPaywallCache: PaywallCacheProtocol {
    public static let defaultSchemaIdentifier = "com.broadapps.platform.paywall"
    public static let currentVersion = 1

    private let repository: any CacheRepositoryProtocol
    private let subject: EntitlementSubject
    private let schemaIdentifier: String
    private let version: Int
    private let freshTimeToLive: TimeInterval
    private let maximumStaleAge: TimeInterval
    private let unavailableError: AppError
    private let clock: CacheClock

    public init(
        repository: any CacheRepositoryProtocol,
        subject: EntitlementSubject,
        freshTimeToLive: TimeInterval = 15 * 60,
        maximumStaleAge: TimeInterval = 24 * 60 * 60,
        schemaIdentifier: String = VersionedPaywallCache.defaultSchemaIdentifier,
        version: Int = VersionedPaywallCache.currentVersion,
        unavailableError: AppError,
        clock: CacheClock = .system
    ) {
        precondition(
            freshTimeToLive.isFinite && freshTimeToLive > 0,
            "Paywall cache fresh time to live must be finite and positive"
        )
        precondition(
            maximumStaleAge.isFinite && maximumStaleAge >= freshTimeToLive,
            "Paywall cache stale age must be finite and at least the fresh time to live"
        )
        precondition(
            !schemaIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            "Paywall cache schema identifier must not be empty"
        )
        precondition(version > 0, "Paywall cache version must be greater than zero")

        self.repository = repository
        self.subject = subject
        self.freshTimeToLive = freshTimeToLive
        self.maximumStaleAge = maximumStaleAge
        self.schemaIdentifier = schemaIdentifier
        self.version = version
        self.unavailableError = unavailableError
        self.clock = clock
    }

    public func readPaywall(
        for placementID: PlacementID
    ) async -> PaywallCacheReadOutcome {
        let cacheKey = key(for: placementID)

        do {
            switch try await repository.read(cacheKey) {
            case let .fresh(envelope):
                guard isUsable(envelope.value, for: placementID) else {
                    await remove(envelope.value, for: cacheKey)
                    return .missing
                }
                return .fresh(envelope.value)

            case let .stale(envelope):
                guard isUsable(envelope.value, for: placementID) else {
                    await remove(envelope.value, for: cacheKey)
                    return .missing
                }
                return .stale(envelope.value)

            case .missing:
                return .missing
            }
        } catch {
            return .unavailable(unavailableError)
        }
    }

    public func writePaywall(
        _ paywall: PaywallPayload,
        for placementID: PlacementID
    ) async -> PaywallCacheWriteOutcome {
        guard isUsable(paywall, for: placementID) else {
            return .unavailable(unavailableError)
        }

        do {
            try await repository.write(paywall, for: key(for: placementID))
            return .stored
        } catch {
            return .unavailable(unavailableError)
        }
    }
}

private extension VersionedPaywallCache {
    func key(
        for placementID: PlacementID
    ) -> CacheKey<PaywallPayload> {
        CacheKey(
            name: "\(lengthPrefixed(subject.cacheKeyComponent))#\(lengthPrefixed(placementID.rawValue))",
            schemaIdentifier: schemaIdentifier,
            version: version,
            policy: CachePolicy(timeToLive: freshTimeToLive)
        )
    }

    func isUsable(
        _ paywall: PaywallPayload,
        for placementID: PlacementID
    ) -> Bool {
        guard
            !paywall.products.isEmpty,
            paywall.origin.resolvedPlacementID == placementID
        else {
            return false
        }

        let age = clock.now().timeIntervalSince(paywall.fetchedAt)
        return age.isFinite && age >= 0 && age <= maximumStaleAge
    }

    func remove(
        _ paywall: PaywallPayload,
        for key: CacheKey<PaywallPayload>
    ) async {
        _ = try? await repository.remove(key, ifMatching: paywall)
    }

    func lengthPrefixed(_ value: String) -> String {
        "\(value.utf8.count)#\(value)"
    }
}
