import BroadCore
import Foundation

public actor CachedStorefrontRepository:
    StorefrontRepositoryProtocol,
    LiveStorefrontRepositoryProtocol,
    StorefrontHintRepositoryProtocol {
    private let client: any StoreKitStorefrontClientProtocol
    private let cache: any CacheRepositoryProtocol
    private let cacheKey: CacheKey<Storefront>
    private let cacheTimeToLive: TimeInterval
    private let clock: CacheClock

    private var sessionValue: (storefront: Storefront, expiresAt: Date)?

    public init(
        client: any StoreKitStorefrontClientProtocol = StoreKitCurrentStorefrontClient(),
        cache: any CacheRepositoryProtocol,
        cacheTimeToLive: TimeInterval = 24 * 60 * 60,
        clock: CacheClock = .system
    ) {
        precondition(
            cacheTimeToLive.isFinite && cacheTimeToLive > 0,
            "Storefront cache time to live must be finite and positive"
        )

        self.client = client
        self.cache = cache
        self.cacheTimeToLive = cacheTimeToLive
        self.clock = clock
        cacheKey = CacheKey(
            name: "current-app-store-storefront",
            schemaIdentifier: "dev.broadapps.monetization.storefront",
            version: 1,
            policy: CachePolicy(timeToLive: cacheTimeToLive)
        )
    }

    public func currentStorefront() async -> StorefrontResolution {
        await liveCurrentStorefront()
    }

    public func cachedStorefrontHint() async -> StorefrontResolution {
        if let sessionValue, clock.now() < sessionValue.expiresAt {
            return .available(sessionValue.storefront)
        }

        guard let cached = try? await cache.read(cacheKey) else {
            return .unavailable(RUBillingSafeErrors.storefrontUnavailable)
        }

        switch cached {
        case let .fresh(envelope):
            sessionValue = (envelope.value, envelope.expiresAt)
            return .available(envelope.value)
        case .stale, .missing:
            return .unavailable(RUBillingSafeErrors.storefrontUnavailable)
        }
    }

    public func liveCurrentStorefront() async -> StorefrontResolution {
        switch await client.loadCurrentStorefront() {
        case let .available(storefront):
            guard !Task.isCancelled else {
                return .unavailable(RUBillingSafeErrors.storefrontUnavailable)
            }
            let now = clock.now()
            let expiresAt = now.addingTimeInterval(cacheTimeToLive)
            if now.timeIntervalSinceReferenceDate.isFinite,
               expiresAt.timeIntervalSinceReferenceDate.isFinite {
                sessionValue = (storefront, expiresAt)
            }
            try? await cache.write(storefront, for: cacheKey)
            return .available(storefront)
        case .unavailable:
            return .unavailable(RUBillingSafeErrors.storefrontUnavailable)
        }
    }
}
