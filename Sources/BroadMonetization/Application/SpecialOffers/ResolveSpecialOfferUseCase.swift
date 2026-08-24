import BroadCore
import Foundation

public actor ResolveSpecialOfferUseCase: ResolveSpecialOfferUseCaseProtocol {
    private struct InFlightResolution {
        let identifier: UUID
        let configuration: SpecialOfferConfiguration
        let task: Task<SpecialOfferResolution, Never>
    }

    private let loadPaywallUseCase: any LoadPaywallUseCaseProtocol
    private let presentationLifecycle: any PaywallPresentationLifecycleProtocol

    private var inFlightResolutions: [PlacementID: InFlightResolution] = [:]

    /// Preferred initializer. The platform campaign is authorized by the
    /// current Adapty payload and does not need persisted timing state.
    public init(
        loadPaywallUseCase: any LoadPaywallUseCaseProtocol,
        presentationLifecycle: any PaywallPresentationLifecycleProtocol
    ) {
        self.loadPaywallUseCase = loadPaywallUseCase
        self.presentationLifecycle = presentationLifecycle
    }

    /// Source-compatible initializer for applications created before the
    /// recurring display countdown replaced real campaign expiration.
    public init(
        loadPaywallUseCase: any LoadPaywallUseCaseProtocol,
        stateRepository _: any SpecialOfferStateRepositoryProtocol,
        presentationLifecycle: any PaywallPresentationLifecycleProtocol,
        clock _: SpecialOfferClock = .untrusted
    ) {
        self.init(
            loadPaywallUseCase: loadPaywallUseCase,
            presentationLifecycle: presentationLifecycle
        )
    }

    public func callAsFunction(
        configuration: SpecialOfferConfiguration?
    ) async -> SpecialOfferResolution {
        // This guard deliberately precedes every dependency access. A project
        // that passes nil performs no paywall, cache or network work.
        guard let configuration else {
            return SpecialOfferResolution(
                state: .unavailable(.notConfigured),
                paywall: nil
            )
        }

        while let inFlight = inFlightResolutions[configuration.placementID] {
            // Never hand one provider presentation to two callers. Wait for the
            // current owner, then resolve a fresh presentation for this caller.
            _ = await inFlight.task.value
            removeIfCurrent(inFlight, for: configuration.placementID)
        }

        let identifier = UUID()
        let loadPaywallUseCase = loadPaywallUseCase
        let presentationLifecycle = presentationLifecycle
        let task = Task<SpecialOfferResolution, Never> {
            await Self.resolveConfiguredOffer(
                configuration,
                loadPaywallUseCase: loadPaywallUseCase,
                presentationLifecycle: presentationLifecycle
            )
        }
        let inFlight = InFlightResolution(
            identifier: identifier,
            configuration: configuration,
            task: task
        )
        inFlightResolutions[configuration.placementID] = inFlight
        return await finish(inFlight, for: configuration.placementID)
    }
}

private extension ResolveSpecialOfferUseCase {
    private func finish(
        _ resolution: InFlightResolution,
        for placementID: PlacementID
    ) async -> SpecialOfferResolution {
        let result = await resolution.task.value
        removeIfCurrent(resolution, for: placementID)
        if Task.isCancelled, let paywall = result.paywall {
            await presentationLifecycle.presentationDidEnd(
                PaywallAnalyticsContext(paywall: paywall)
            )
            return Self.unavailable(.paywallUnavailable)
        }
        return result
    }

    private func removeIfCurrent(
        _ resolution: InFlightResolution,
        for placementID: PlacementID
    ) {
        if inFlightResolutions[placementID]?.identifier == resolution.identifier {
            inFlightResolutions[placementID] = nil
        }
    }

    static func resolveConfiguredOffer(
        _ configuration: SpecialOfferConfiguration,
        loadPaywallUseCase: any LoadPaywallUseCaseProtocol,
        presentationLifecycle: any PaywallPresentationLifecycleProtocol
    ) async -> SpecialOfferResolution {
        // The repository first obtains the paywall and all of its products,
        // preserving provider order and exact raw-product references. Only then
        // does this resolver decide whether the second presentation is allowed.
        let loadOutcome = await loadPaywallUseCase(
            PaywallLoadRequest(placementID: configuration.placementID)
        )
        guard case let .loaded(paywall) = loadOutcome else {
            return unavailable(.paywallUnavailable)
        }
        guard isExpectedOrigin(paywall.origin, configuration: configuration) else {
            await end(paywall, using: presentationLifecycle)
            return unavailable(.paywallUnavailable)
        }

        guard paywall.remoteConfigurationProvenance
            .authorizesSpecialOfferPresentation
        else {
            await end(paywall, using: presentationLifecycle)
            return unavailable(.disabledByRemoteConfiguration)
        }

        // `special_offer = true` in the current provider payload is the whole
        // campaign gate. Display countdown, persisted dates and server time do
        // not participate in eligibility.
        guard paywall.remoteConfiguration.specialOffer?.isEnabled == true else {
            await end(paywall, using: presentationLifecycle)
            return unavailable(.disabledByRemoteConfiguration)
        }

        return SpecialOfferResolution(state: .eligible, paywall: paywall)
    }

    static func isExpectedOrigin(
        _ origin: PaywallOrigin,
        configuration: SpecialOfferConfiguration
    ) -> Bool {
        guard origin.requestedPlacementID == configuration.placementID else {
            return false
        }
        if origin.usedFallback {
            return origin.resolvedPlacementID == .main
        }
        return origin.resolvedPlacementID == configuration.placementID
    }

    static func unavailable(
        _ reason: SpecialOfferUnavailableReason
    ) -> SpecialOfferResolution {
        SpecialOfferResolution(state: .unavailable(reason), paywall: nil)
    }

    static func end(
        _ paywall: PaywallPayload,
        using lifecycle: any PaywallPresentationLifecycleProtocol
    ) async {
        await lifecycle.presentationDidEnd(
            PaywallAnalyticsContext(paywall: paywall)
        )
    }
}
