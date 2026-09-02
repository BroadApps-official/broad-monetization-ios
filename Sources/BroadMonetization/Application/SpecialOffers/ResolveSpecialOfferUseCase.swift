import BroadCore
import Foundation

public actor ResolveSpecialOfferUseCase: ResolveSpecialOfferUseCaseProtocol {
    /// Default campaign window and quiet period when a configuration leaves them
    /// unset: one day on, one day off ("day-through-day").
    public static let defaultWindowDuration: TimeInterval = 24 * 60 * 60
    public static let defaultCooldownDuration: TimeInterval = 24 * 60 * 60

    private struct InFlightResolution {
        let identifier: UUID
        let configuration: SpecialOfferConfiguration
        let task: Task<SpecialOfferResolution, Never>
    }

    private let loadPaywallUseCase: any LoadPaywallUseCaseProtocol
    private let presentationLifecycle: any PaywallPresentationLifecycleProtocol
    private let stateRepository: (any SpecialOfferStateRepositoryProtocol)?
    private let clock: SpecialOfferClock?

    private var inFlightResolutions: [PlacementID: InFlightResolution] = [:]

    /// Preferred initializer for an untimed offer: eligibility follows the current
    /// provider payload only. The offer is shown whenever the placement resolves
    /// to its own enabled paywall; no window, cadence or clock is consulted.
    public init(
        loadPaywallUseCase: any LoadPaywallUseCaseProtocol,
        presentationLifecycle: any PaywallPresentationLifecycleProtocol
    ) {
        self.loadPaywallUseCase = loadPaywallUseCase
        self.presentationLifecycle = presentationLifecycle
        stateRepository = nil
        clock = nil
    }

    /// Timed initializer: activates the cadence engine. The offer runs for a
    /// window, is shown on every dismissal during it, then rests for a cooldown
    /// before the next window opens. Timing uses trusted server time from `clock`
    /// and persisted window state from `stateRepository`; both are required for a
    /// timed offer, or it fails closed as untrusted.
    public init(
        loadPaywallUseCase: any LoadPaywallUseCaseProtocol,
        stateRepository: any SpecialOfferStateRepositoryProtocol,
        presentationLifecycle: any PaywallPresentationLifecycleProtocol,
        clock: SpecialOfferClock = .untrusted
    ) {
        self.loadPaywallUseCase = loadPaywallUseCase
        self.presentationLifecycle = presentationLifecycle
        self.stateRepository = stateRepository
        self.clock = clock
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
        let stateRepository = stateRepository
        let clock = clock
        let task = Task<SpecialOfferResolution, Never> {
            await Self.resolveConfiguredOffer(
                configuration,
                loadPaywallUseCase: loadPaywallUseCase,
                presentationLifecycle: presentationLifecycle,
                stateRepository: stateRepository,
                clock: clock
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
        presentationLifecycle: any PaywallPresentationLifecycleProtocol,
        stateRepository: (any SpecialOfferStateRepositoryProtocol)?,
        clock: SpecialOfferClock?
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
        // Refuse a substituted or fallback paywall: a campaign must sell its own
        // placement, never an invented discount on the main paywall.
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

        // Absence means the campaign is on: only an explicit `special_offer=false`
        // in the current provider payload stops it.
        guard paywall.remoteConfiguration.specialOffer?.isEnabled != false else {
            await end(paywall, using: presentationLifecycle)
            return unavailable(.disabledByRemoteConfiguration)
        }

        guard !paywall.products.isEmpty else {
            await end(paywall, using: presentationLifecycle)
            return unavailable(.ineligible)
        }

        guard let stateRepository, let clock else {
            // Untimed offer: eligible whenever the enabled own placement loads.
            return SpecialOfferResolution(state: .eligible, paywall: paywall)
        }

        return await resolveTimedOffer(
            configuration,
            paywall: paywall,
            presentationLifecycle: presentationLifecycle,
            stateRepository: stateRepository,
            clock: clock
        )
    }

    static func resolveTimedOffer(
        _ configuration: SpecialOfferConfiguration,
        paywall: PaywallPayload,
        presentationLifecycle: any PaywallPresentationLifecycleProtocol,
        stateRepository: any SpecialOfferStateRepositoryProtocol,
        clock: SpecialOfferClock
    ) async -> SpecialOfferResolution {
        guard case let .synchronized(trustedTime) = await clock.reading() else {
            // Fail closed: a timed offer never runs on an unverified clock.
            await end(paywall, using: presentationLifecycle)
            return unavailable(.untrustedTime)
        }

        guard case let .loaded(persistedState) = await stateRepository.state(
            for: configuration
        ) else {
            await end(paywall, using: presentationLifecycle)
            return unavailable(.persistenceUnavailable)
        }

        let windowDuration = configuration.windowDuration ?? defaultWindowDuration
        let cooldownDuration = configuration.cooldownDuration ?? defaultCooldownDuration
        let nextState = nextState(
            from: persistedState,
            now: trustedTime.date,
            windowDuration: windowDuration,
            cooldownDuration: cooldownDuration
        )

        switch nextState {
        case let .active(window):
            _ = await stateRepository.save(.active(window), for: configuration)
            return SpecialOfferResolution(
                state: .active(window),
                paywall: paywall,
                trustedTime: trustedTime
            )
        case let .cooldown(until):
            _ = await stateRepository.save(.cooldown(until: until), for: configuration)
            await end(paywall, using: presentationLifecycle)
            return SpecialOfferResolution(state: .cooldown(until: until), paywall: nil)
        case .eligible, .expired, .unavailable:
            // `nextState(from:...)` only ever returns `.active` or `.cooldown`.
            await end(paywall, using: presentationLifecycle)
            return unavailable(.ineligible)
        }
    }

    /// The day-through-day state machine. Asking is what opens a window: an
    /// active window is shown on every dismissal until it expires, then a
    /// cooldown of silence, then the next ask opens a fresh window.
    static func nextState(
        from state: SpecialOfferState,
        now: Date,
        windowDuration: TimeInterval,
        cooldownDuration: TimeInterval
    ) -> SpecialOfferState {
        switch state {
        case let .active(window):
            if now < window.expiresAt {
                return .active(window)
            }
            let cooldownEnd = window.expiresAt.addingTimeInterval(cooldownDuration)
            if now < cooldownEnd {
                return .cooldown(until: cooldownEnd)
            }
            return .active(newWindow(now: now, windowDuration: windowDuration))
        case let .cooldown(until):
            if now < until {
                return .cooldown(until: until)
            }
            return .active(newWindow(now: now, windowDuration: windowDuration))
        case .eligible, .expired, .unavailable:
            return .active(newWindow(now: now, windowDuration: windowDuration))
        }
    }

    static func newWindow(
        now: Date,
        windowDuration: TimeInterval
    ) -> SpecialOfferWindow {
        SpecialOfferWindow(
            startedAt: now,
            expiresAt: now.addingTimeInterval(windowDuration)
        )
    }

    static func isExpectedOrigin(
        _ origin: PaywallOrigin,
        configuration: SpecialOfferConfiguration
    ) -> Bool {
        !origin.usedFallback
            && origin.requestedPlacementID == configuration.placementID
            && origin.resolvedPlacementID == configuration.placementID
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
