import BroadCore

/// Connects provider outages or missing RU ID matches to the host's backend.
/// Without exact matches, all default subscriptions are selected. A received
/// false/invalid/missing flag is different from receiving no configuration.
/// Existing LoadPaywallUseCase remains unchanged; install this in its place.
public struct LoadPaywallWithRUFallbackUseCase: LoadPaywallUseCaseProtocol {
    private let provider: any RUFallbackPaywallRepositoryProtocol
    private let catalog: any FreshRUCatalogRepositoryProtocol
    private let storefront: any StorefrontRepositoryProtocol
    private let gate: RUBillingGate
    private let cache: (any PaywallCacheProtocol)?
    private let analytics: any MonetizationAnalyticsProtocol
    private let lifecycle: any PaywallPresentationLifecycleProtocol
    private let staleLoadError: AppError

    public init(
        provider: any RUFallbackPaywallRepositoryProtocol,
        catalog: any FreshRUCatalogRepositoryProtocol,
        storefront: any StorefrontRepositoryProtocol,
        gate: RUBillingGate,
        cache: (any PaywallCacheProtocol)? = nil,
        analytics: any MonetizationAnalyticsProtocol,
        presentationLifecycle: any PaywallPresentationLifecycleProtocol = NoOpPaywallPresentationLifecycle(),
        staleLoadError: AppError
    ) {
        self.provider = provider
        self.catalog = catalog
        self.storefront = storefront
        self.gate = gate
        self.cache = cache
        self.analytics = NonBlockingMonetizationAnalytics.wrapping(analytics)
        lifecycle = presentationLifecycle
        self.staleLoadError = staleLoadError
    }

    public func callAsFunction(_ request: PaywallLoadRequest) async -> PaywallLoadOutcome {
        let context = PaywallLoadAnalyticsContext(attemptID: .generated(), request: request)
        await analytics.track(.paywallLoadStarted(context))
        // Per-call evidence prevents a simultaneous placement request from
        // replacing this attempt's explicit prohibition.
        let evidence = RUFallbackAttemptRecorder(provider: provider)
        let ordinary = await LoadPaywallUseCase(
            repository: evidence,
            cache: cache,
            analytics: NoOpMonetizationAnalytics(),
            presentationLifecycle: lifecycle,
            staleLoadError: staleLoadError
        )(request)
        let resolved = await resolve(ordinary, request: request, evidence: evidence)
        let outcome = if Task.isCancelled {
            await cancelled(resolved)
        } else {
            resolved
        }
        switch outcome {
        case let .loaded(paywall):
            await analytics.track(.paywallLoadSuccess(context, paywall: PaywallAnalyticsContext(paywall: paywall)))
        case let .unavailable(error):
            await analytics.track(.paywallLoadFailed(context, failure: MonetizationAnalyticsFailure(error: error)))
        }
        return outcome
    }

    private func cancelled(_ outcome: PaywallLoadOutcome) async -> PaywallLoadOutcome {
        if case let .loaded(payload) = outcome {
            await lifecycle.presentationDidEnd(PaywallAnalyticsContext(paywall: payload))
        }
        return .unavailable(staleLoadError)
    }

    private func resolve(
        _ ordinary: PaywallLoadOutcome,
        request: PaywallLoadRequest,
        evidence: RUFallbackAttemptRecorder
    ) async -> PaywallLoadOutcome {
        guard !Task.isCancelled else { return await cancelled(ordinary) }
        let providerPaywall = availableProviderPaywall(in: ordinary)
        guard request.placementID != .specialOffer, request.placementID != .tokens,
              let configuration = await evidence.fallbackConfiguration(for: providerPaywall)
        else { return ordinary }
        let currentStorefront: Storefront? = switch await storefront.currentStorefront() {
        case let .available(value): value
        case .unavailable: nil
        }
        guard !Task.isCancelled,
              gate.allows(remoteConfiguration: configuration, storefront: currentStorefront)
        else { return ordinary }
        guard case let .loaded(payload) = await catalog.loadFreshCatalog() else { return ordinary }
        guard !Task.isCancelled else { return await cancelled(ordinary) }
        let selection = RUExperimentCatalogSelector().select(
            productIDs: providerPaywall?.products.map(\.productID) ?? [], in: payload, kind: .subscriptions
        )
        // A working provider catalog with any exact matches keeps its complete
        // array and raw SDK handles. Defaults never replace one unmatched card.
        if providerPaywall != nil, selection.source == .placementMatches {
            return ordinary
        }
        let products = RUFallbackProductIdentity.products(in: payload, selectedRows: selection.products)
        guard products.contains(where: \.isEligibleForGenericPurchase) else { return ordinary }
        if case let .loaded(discarded) = ordinary {
            await lifecycle.presentationDidEnd(PaywallAnalyticsContext(paywall: discarded))
        }
        var fallbackConfiguration = RemotePaywallConfiguration.empty
        fallbackConfiguration.authorizesRUProviderFallback = true
        return .loaded(PaywallPayload(
            presentationID: .generated(),
            paywallReference: PaywallReference(rawValue: "ru-backend-\(PaywallPresentationID.generated().rawValue)"),
            origin: PaywallOrigin(
                requestedPlacementID: request.placementID,
                resolvedPlacementID: request.placementID,
                catalogSource: .ruBackend
            ),
            products: products,
            remoteConfiguration: fallbackConfiguration,
            // No assertion that Adapty returned a verified remote response.
            remoteConfigurationProvenance: .legacyUnqualified,
            fetchedAt: payload.fetchedAt
        ))
    }

    private func availableProviderPaywall(in outcome: PaywallLoadOutcome) -> PaywallPayload? {
        guard case let .loaded(paywall) = outcome,
              !paywall.products.isEmpty, paywall.origin.catalogSource != .cache else { return nil }
        return paywall
    }
}

private actor RUFallbackAttemptRecorder: PaywallRepositoryProtocol {
    let provider: any RUFallbackPaywallRepositoryProtocol
    private var hasUnavailableProviderProducts = false
    private var isProhibited = false

    init(provider: any RUFallbackPaywallRepositoryProtocol) {
        self.provider = provider
    }

    func loadPaywall(for placementID: PlacementID) async -> PaywallLoadOutcome {
        let attempt = await provider.loadRUFallbackAttempt(for: placementID)
        switch attempt.availability {
        case .notConfigured:
            // Optional placements already fall back to main. Only an absent
            // main mapping is a composition error, not a provider outage.
            if placementID == .main {
                isProhibited = true
            }
        case .available:
            // Any explicit prohibition in a response wins within this attempt,
            // including an empty requested placement followed by main.
            if case let .loaded(payload) = attempt.outcome {
                // A successful SDK request can still contain zero products.
                // Treat it like unavailable products, preserving its gate.
                hasUnavailableProviderProducts = hasUnavailableProviderProducts || payload.products.isEmpty
                if payload.remoteConfiguration.ruBillingGateDecision != .enabled {
                    isProhibited = true
                }
            }
        case let .unavailable(configuration):
            hasUnavailableProviderProducts = true
            if let configuration, configuration.ruBillingGateDecision != .enabled {
                isProhibited = true
            }
        }
        return attempt.outcome
    }

    func fallbackConfiguration(for providerPaywall: PaywallPayload?) -> RemotePaywallConfiguration? {
        guard !isProhibited else { return nil }
        if let providerPaywall {
            // With working products, the existing fresh-configuration gate is
            // required before looking for backend matches/defaults.
            guard providerPaywall.remoteConfiguration.authorizesRUBillingPresentation else { return nil }
            return providerPaywall.remoteConfiguration
        }
        guard hasUnavailableProviderProducts else { return nil }
        // The capability is never serialized. It cannot activate experiments
        // or Special Offer, or pretend the provider sent ru_pay=true.
        var configuration = RemotePaywallConfiguration.empty
        configuration.authorizesRUProviderFallback = true
        return configuration
    }
}
