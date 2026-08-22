import BroadCore

public actor LoadPaywallUseCase: LoadPaywallUseCaseProtocol {
    private let repository: any PaywallRepositoryProtocol
    private let cache: (any PaywallCacheProtocol)?
    private let analytics: any MonetizationAnalyticsProtocol
    private let presentationLifecycle: any PaywallPresentationLifecycleProtocol
    private let staleLoadError: AppError

    public init(
        repository: any PaywallRepositoryProtocol,
        cache: (any PaywallCacheProtocol)? = nil,
        analytics: any MonetizationAnalyticsProtocol,
        presentationLifecycle: any PaywallPresentationLifecycleProtocol =
            NoOpPaywallPresentationLifecycle(),
        staleLoadError: AppError
    ) {
        self.repository = repository
        self.cache = cache
        self.analytics = NonBlockingMonetizationAnalytics.wrapping(analytics)
        self.presentationLifecycle = presentationLifecycle
        self.staleLoadError = staleLoadError
    }

    public func callAsFunction(
        _ request: PaywallLoadRequest
    ) async -> PaywallLoadOutcome {
        let analyticsContext = PaywallLoadAnalyticsContext(
            attemptID: .generated(),
            request: request
        )
        await analytics.track(.paywallLoadStarted(analyticsContext))

        let primary = await loadCandidate(
            placementID: request.placementID,
            requestedPlacementID: request.placementID,
            fallbackReason: nil
        )
        guard !Task.isCancelled else {
            await endPresentation(in: primary)
            return await failStaleLoad(context: analyticsContext)
        }

        if case let .usable(paywall) = primary {
            return await succeed(paywall, context: analyticsContext)
        }

        let primaryFailure = primary.failure
        guard request.shouldAttemptFallback else {
            return await finishWithoutFallback(
                primary,
                context: analyticsContext
            )
        }

        // This candidate will not be presented once fallback begins. Release
        // its provider handles even when it contained an empty product array.
        await endPresentation(in: primary)

        let fallback = await loadCandidate(
            placementID: request.fallbackPlacementID,
            requestedPlacementID: request.placementID,
            fallbackReason: primaryFailure.reason
        )
        guard !Task.isCancelled else {
            await endPresentation(in: fallback)
            return await failStaleLoad(context: analyticsContext)
        }

        switch fallback {
        case let .usable(paywall), let .empty(paywall, _):
            // The returned payload is the resolved fallback candidate. Its
            // Remote Config belongs to `fallbackPlacementID` (normally main),
            // while `origin` still records the originally requested placement.
            return await succeed(paywall, context: analyticsContext)
        case let .unavailable(error, _):
            let finalError = primaryFailure.error ?? error
            await analytics.track(
                .paywallLoadFailed(
                    analyticsContext,
                    failure: MonetizationAnalyticsFailure(error: finalError)
                )
            )
            return .unavailable(finalError)
        }
    }
}

private extension LoadPaywallUseCase {
    enum Candidate {
        case usable(PaywallPayload)
        case empty(PaywallPayload, PaywallFallbackReason)
        case unavailable(AppError, PaywallFallbackReason)

        var failure: (reason: PaywallFallbackReason, error: AppError?) {
            switch self {
            case .usable:
                (.unavailable, nil)
            case let .empty(_, reason):
                (reason, nil)
            case let .unavailable(error, reason):
                (reason, error)
            }
        }
    }

    func loadCandidate(
        placementID: PlacementID,
        requestedPlacementID: PlacementID,
        fallbackReason: PaywallFallbackReason?
    ) async -> Candidate {
        let remote = await repository.loadPaywall(for: placementID)
        switch remote {
        case let .loaded(paywall):
            if !paywall.products.isEmpty, let cache {
                _ = await cache.writePaywall(paywall, for: placementID)
            }
            let resolved = reorigin(
                paywall,
                requestedPlacementID: requestedPlacementID,
                resolvedPlacementID: placementID,
                catalogSource: paywall.origin.catalogSource,
                fallbackReason: fallbackReason
            )
            guard resolved.products.isEmpty else {
                return .usable(resolved)
            }

            if let cached = await usableCachedPaywall(
                placementID: placementID,
                requestedPlacementID: requestedPlacementID,
                fallbackReason: fallbackReason
            ) {
                await presentationLifecycle.presentationDidEnd(
                    PaywallAnalyticsContext(paywall: resolved)
                )
                return .usable(cached)
            }
            return .empty(resolved, .emptyProducts)

        case let .unavailable(error):
            if let cached = await usableCachedPaywall(
                placementID: placementID,
                requestedPlacementID: requestedPlacementID,
                fallbackReason: fallbackReason
            ) {
                return .usable(cached)
            }
            return .unavailable(error, .unavailable)
        }
    }

    func usableCachedPaywall(
        placementID: PlacementID,
        requestedPlacementID: PlacementID,
        fallbackReason: PaywallFallbackReason?
    ) async -> PaywallPayload? {
        guard let cache else {
            return nil
        }

        let cached = await cache.readPaywall(for: placementID)
        let paywall: PaywallPayload
        switch cached {
        case let .fresh(value), let .stale(value):
            paywall = value.preparedForNewPresentation()
        case .missing, .unavailable:
            return nil
        }
        guard !paywall.products.isEmpty else {
            return nil
        }
        return reorigin(
            paywall,
            requestedPlacementID: requestedPlacementID,
            resolvedPlacementID: placementID,
            catalogSource: .cache,
            fallbackReason: fallbackReason
        )
    }

    func reorigin(
        _ paywall: PaywallPayload,
        requestedPlacementID: PlacementID,
        resolvedPlacementID: PlacementID,
        catalogSource: CatalogSource,
        fallbackReason: PaywallFallbackReason?
    ) -> PaywallPayload {
        PaywallPayload(
            presentationID: paywall.presentationID,
            paywallReference: paywall.paywallReference,
            variationID: paywall.variationID,
            origin: PaywallOrigin(
                requestedPlacementID: requestedPlacementID,
                resolvedPlacementID: resolvedPlacementID,
                catalogSource: catalogSource,
                fallbackReason: requestedPlacementID == resolvedPlacementID
                    ? nil
                    : fallbackReason ?? .unavailable
            ),
            products: paywall.products,
            remoteConfiguration: paywall.remoteConfiguration,
            // Once BroadMonetization restores a payload from its own cache, it
            // must lose every positive provider-gate capability even if the
            // original Adapty presentation was provider-managed.
            remoteConfigurationProvenance: catalogSource == .cache
                ? .platformCache
                : paywall.remoteConfigurationProvenance,
            fetchedAt: paywall.fetchedAt
        )
    }

    func finishWithoutFallback(
        _ candidate: Candidate,
        context: PaywallLoadAnalyticsContext
    ) async -> PaywallLoadOutcome {
        switch candidate {
        case let .usable(paywall), let .empty(paywall, _):
            return await succeed(paywall, context: context)
        case let .unavailable(error, _):
            await analytics.track(
                .paywallLoadFailed(
                    context,
                    failure: MonetizationAnalyticsFailure(error: error)
                )
            )
            return .unavailable(error)
        }
    }

    func succeed(
        _ paywall: PaywallPayload,
        context: PaywallLoadAnalyticsContext
    ) async -> PaywallLoadOutcome {
        await analytics.track(
            .paywallLoadSuccess(
                context,
                paywall: PaywallAnalyticsContext(paywall: paywall)
            )
        )
        return .loaded(paywall)
    }

    func failStaleLoad(
        context: PaywallLoadAnalyticsContext
    ) async -> PaywallLoadOutcome {
        await analytics.track(
            .paywallLoadFailed(
                context,
                failure: MonetizationAnalyticsFailure(error: staleLoadError)
            )
        )
        return .unavailable(staleLoadError)
    }

    func endPresentation(
        in candidate: Candidate
    ) async {
        let paywall: PaywallPayload
        switch candidate {
        case let .usable(value), let .empty(value, _):
            paywall = value
        case .unavailable:
            return
        }
        await presentationLifecycle.presentationDidEnd(
            PaywallAnalyticsContext(paywall: paywall)
        )
    }
}
