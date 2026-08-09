import BroadCore
import Foundation

public actor CachedRUCatalogRepository: RUCatalogRepositoryProtocol {
    private let remote: any RUCatalogRepositoryProtocol
    private let cache: any CacheRepositoryProtocol
    private let cacheKey: CacheKey<RUCatalogPayload>
    private let maximumStaleAge: TimeInterval
    private let authorizationBinding: SubjectAuthorizationBinding
    private let clock: CacheClock
    private let legacyCacheKey: CacheKey<RUCatalogPayload>

    private var didCleanLegacyCache = false

    public init(
        remote: any RUCatalogRepositoryProtocol,
        cache: any CacheRepositoryProtocol,
        subject: EntitlementSubject,
        authorizationBinding: SubjectAuthorizationBinding,
        freshTimeToLive: TimeInterval = 15 * 60,
        maximumStaleAge: TimeInterval = 24 * 60 * 60,
        clock: CacheClock = .system
    ) {
        precondition(
            freshTimeToLive.isFinite && freshTimeToLive > 0,
            "RU catalog fresh time to live must be finite and positive"
        )
        precondition(
            maximumStaleAge.isFinite && maximumStaleAge >= freshTimeToLive,
            "RU catalog stale age must be finite and at least the fresh time to live"
        )
        precondition(
            authorizationBinding.subject == subject,
            "RU catalog binding must match the exact subject"
        )

        self.remote = remote
        self.cache = cache
        cacheKey = CacheKey(
            name: "ru-billing-catalog-\(subject.cacheKeyComponent)",
            schemaIdentifier: "dev.broadapps.monetization.ru-catalog",
            version: 1,
            policy: CachePolicy(timeToLive: freshTimeToLive)
        )
        legacyCacheKey = CacheKey(
            name: "ru-billing-catalog",
            schemaIdentifier: "dev.broadapps.monetization.ru-catalog",
            version: 1,
            policy: CachePolicy(timeToLive: freshTimeToLive)
        )
        self.maximumStaleAge = maximumStaleAge
        self.authorizationBinding = authorizationBinding
        self.clock = clock
    }

    public func loadCatalog() async -> RUCatalogLoadOutcome {
        guard authorizationBinding.isCurrent() else {
            return .unavailable(RUBillingSafeErrors.catalogUnavailable)
        }
        await cleanLegacyUnscopedCacheIfNeeded()
        guard authorizationBinding.isCurrent() else {
            return .unavailable(RUBillingSafeErrors.catalogUnavailable)
        }

        let outcome = await remote.loadCatalog()
        switch outcome {
        case let .loaded(payload):
            return await persist(payload)
        case let .unavailable(remoteError):
            return await cachedFallback(remoteError: remoteError)
        }
    }

    private func persist(
        _ payload: RUCatalogPayload
    ) async -> RUCatalogLoadOutcome {
        guard authorizationBinding.isCurrent() else {
            return .unavailable(RUBillingSafeErrors.catalogUnavailable)
        }
        try? await cache.write(payload, for: cacheKey)
        guard authorizationBinding.isCurrent() else {
            _ = try? await cache.remove(cacheKey, ifMatching: payload)
            return .unavailable(RUBillingSafeErrors.catalogUnavailable)
        }
        return .loaded(payload)
    }

    private func cachedFallback(
        remoteError: AppError
    ) async -> RUCatalogLoadOutcome {
        guard authorizationBinding.isCurrent() else {
            return .unavailable(RUBillingSafeErrors.catalogUnavailable)
        }

        let cached: CacheReadResult<RUCatalogPayload>
        do {
            cached = try await cache.read(cacheKey)
        } catch {
            try? await cache.remove(cacheKey)
            return .unavailable(remoteError)
        }
        guard authorizationBinding.isCurrent() else {
            return .unavailable(RUBillingSafeErrors.catalogUnavailable)
        }
        return resolveCached(cached, remoteError: remoteError)
    }

    private func resolveCached(
        _ cached: CacheReadResult<RUCatalogPayload>,
        remoteError: AppError
    ) -> RUCatalogLoadOutcome {
        switch cached {
        case let .fresh(envelope):
            return .loaded(envelope.value)
        case let .stale(envelope):
            let age = clock.now().timeIntervalSince(envelope.value.fetchedAt)
            guard age.isFinite, age >= 0, age <= maximumStaleAge else {
                return .unavailable(remoteError)
            }
            return .loaded(envelope.value)
        case .missing:
            return .unavailable(remoteError)
        }
    }

    private func cleanLegacyUnscopedCacheIfNeeded() async {
        guard !didCleanLegacyCache else {
            return
        }

        didCleanLegacyCache = true
        try? await cache.remove(legacyCacheKey)
    }
}
