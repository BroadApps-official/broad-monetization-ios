import BroadCore
import Foundation

public actor ResolveSpecialOfferUseCase: ResolveSpecialOfferUseCaseProtocol {
    private struct InFlightResolution {
        let identifier: UUID
        let configuration: SpecialOfferConfiguration
        let task: Task<SpecialOfferResolution, Never>
    }

    private struct EffectiveTime {
        let wallClock: Date
        let trustedTime: SpecialOfferTrustedTime?

        static let untimed = EffectiveTime(
            wallClock: .distantPast,
            trustedTime: nil
        )
    }

    private let loadPaywallUseCase: any LoadPaywallUseCaseProtocol
    private let stateRepository: any SpecialOfferStateRepositoryProtocol
    private let presentationLifecycle: any PaywallPresentationLifecycleProtocol
    private let clock: SpecialOfferClock

    private var inFlightResolutions: [PlacementID: InFlightResolution] = [:]

    public init(
        loadPaywallUseCase: any LoadPaywallUseCaseProtocol,
        stateRepository: any SpecialOfferStateRepositoryProtocol,
        presentationLifecycle: any PaywallPresentationLifecycleProtocol,
        clock: SpecialOfferClock = .untrusted
    ) {
        self.loadPaywallUseCase = loadPaywallUseCase
        self.stateRepository = stateRepository
        self.presentationLifecycle = presentationLifecycle
        self.clock = clock
    }

    public func callAsFunction(
        configuration: SpecialOfferConfiguration?
    ) async -> SpecialOfferResolution {
        // This guard deliberately precedes every dependency access. A project that
        // passes nil performs no paywall/cache/network/timer/persistence work.
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
        let stateRepository = stateRepository
        let presentationLifecycle = presentationLifecycle
        let clock = clock
        let task = Task<SpecialOfferResolution, Never> {
            await Self.resolveConfiguredOffer(
                configuration,
                loadPaywallUseCase: loadPaywallUseCase,
                stateRepository: stateRepository,
                presentationLifecycle: presentationLifecycle,
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
        stateRepository: any SpecialOfferStateRepositoryProtocol,
        presentationLifecycle: any PaywallPresentationLifecycleProtocol,
        clock: SpecialOfferClock
    ) async -> SpecialOfferResolution {
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

        // The current Adapty payload may drive its provider-owned campaign even
        // when the SDK transparently used its managed cache. A payload restored
        // by BroadMonetization itself, or one with unknown legacy provenance,
        // cannot enable the campaign.
        guard paywall.remoteConfigurationProvenance.authorizesProviderManagedFeatureGates else {
            await end(paywall, using: presentationLifecycle)
            return unavailable(.disabledByRemoteConfiguration)
        }

        // The current provider payload is the gate. A missing/invalid/disabled
        // value never resurrects a previous offer, including when `.main`
        // supplied fallback.
        guard let remoteConfiguration = paywall.remoteConfiguration.specialOffer,
              remoteConfiguration.isEnabled
        else {
            await end(paywall, using: presentationLifecycle)
            return unavailable(.disabledByRemoteConfiguration)
        }

        guard case let .loaded(persistedState) = await stateRepository.state(
            for: configuration
        ) else {
            await end(paywall, using: presentationLifecycle)
            return unavailable(.persistenceUnavailable)
        }
        let windowDuration = remoteConfiguration.windowDuration ?? configuration.windowDuration
        let cooldownDuration = remoteConfiguration.cooldownDuration ?? configuration.cooldownDuration
        guard let time = await currentTime(
            state: persistedState,
            windowDuration: windowDuration,
            cooldownDuration: cooldownDuration,
            clock: clock
        ) else {
            await end(paywall, using: presentationLifecycle)
            return unavailable(.untrustedTime)
        }

        let resolution = await resolveState(
            persistedState,
            paywall: paywall,
            configuration: configuration,
            windowDuration: windowDuration,
            cooldownDuration: cooldownDuration,
            time: time,
            stateRepository: stateRepository
        )
        if resolution.paywall == nil {
            await end(paywall, using: presentationLifecycle)
        }
        return resolution
    }

    private static func currentTime(
        state: SpecialOfferState,
        windowDuration: TimeInterval?,
        cooldownDuration: TimeInterval?,
        clock: SpecialOfferClock
    ) async -> EffectiveTime? {
        let requiresTrustedTime = windowDuration != nil
            || cooldownDuration != nil
            || state.hasTemporalBoundary
        guard requiresTrustedTime else {
            // This value cannot open or extend a timed window. It only lets the
            // shared state machine process an untimed offer.
            return .untimed
        }
        guard case let .synchronized(reading) = await clock.reading() else {
            return nil
        }
        return EffectiveTime(
            wallClock: reading.date,
            trustedTime: reading
        )
    }

    private static func resolveState(
        _ state: SpecialOfferState,
        paywall: PaywallPayload,
        configuration: SpecialOfferConfiguration,
        windowDuration: TimeInterval?,
        cooldownDuration: TimeInterval?,
        time: EffectiveTime,
        stateRepository: any SpecialOfferStateRepositoryProtocol
    ) async -> SpecialOfferResolution {
        switch state {
        case let .active(window) where time.wallClock < window.startedAt:
            unavailable(.untrustedTime)
        case let .active(window) where time.wallClock < window.expiresAt:
            SpecialOfferResolution(
                state: .active(window),
                paywall: paywall,
                trustedTime: time.trustedTime
            )
        case let .active(window):
            await resolveExpiredWindow(
                expiredAt: window.expiresAt,
                paywall: paywall,
                configuration: configuration,
                windowDuration: windowDuration,
                cooldownDuration: cooldownDuration,
                time: time,
                stateRepository: stateRepository
            )
        case let .expired(expiredAt):
            await resolveExpiredWindow(
                expiredAt: expiredAt,
                paywall: paywall,
                configuration: configuration,
                windowDuration: windowDuration,
                cooldownDuration: cooldownDuration,
                time: time,
                stateRepository: stateRepository
            )
        case let .cooldown(until) where time.wallClock < until:
            SpecialOfferResolution(state: .cooldown(until: until), paywall: nil)
        case .cooldown:
            await beginWindow(
                paywall: paywall,
                configuration: configuration,
                windowDuration: windowDuration,
                time: time,
                stateRepository: stateRepository
            )
        case .unavailable(.ineligible):
            unavailable(.ineligible)
        case .unavailable, .eligible:
            await beginWindow(
                paywall: paywall,
                configuration: configuration,
                windowDuration: windowDuration,
                time: time,
                stateRepository: stateRepository
            )
        }
    }

    private static func resolveExpiredWindow(
        expiredAt: Date,
        paywall: PaywallPayload,
        configuration: SpecialOfferConfiguration,
        windowDuration: TimeInterval?,
        cooldownDuration: TimeInterval?,
        time: EffectiveTime,
        stateRepository: any SpecialOfferStateRepositoryProtocol
    ) async -> SpecialOfferResolution {
        guard let cooldownDuration else {
            let state = SpecialOfferState.expired(date: expiredAt)
            guard await stateRepository.save(state, for: configuration) else {
                return unavailable(.persistenceUnavailable)
            }
            return SpecialOfferResolution(state: state, paywall: nil)
        }

        let cooldownEnd = expiredAt.addingTimeInterval(cooldownDuration)
        guard cooldownEnd.timeIntervalSinceReferenceDate.isFinite else {
            return unavailable(.persistenceUnavailable)
        }
        guard time.wallClock >= cooldownEnd else {
            let state = SpecialOfferState.cooldown(until: cooldownEnd)
            guard await stateRepository.save(state, for: configuration) else {
                return unavailable(.persistenceUnavailable)
            }
            return SpecialOfferResolution(state: state, paywall: nil)
        }

        return await beginWindow(
            paywall: paywall,
            configuration: configuration,
            windowDuration: windowDuration,
            time: time,
            stateRepository: stateRepository
        )
    }

    private static func beginWindow(
        paywall: PaywallPayload,
        configuration: SpecialOfferConfiguration,
        windowDuration: TimeInterval?,
        time: EffectiveTime,
        stateRepository: any SpecialOfferStateRepositoryProtocol
    ) async -> SpecialOfferResolution {
        guard let windowDuration else {
            return SpecialOfferResolution(state: .eligible, paywall: paywall)
        }

        guard let trustedTime = time.trustedTime else {
            return unavailable(.untrustedTime)
        }
        let expiration = time.wallClock.addingTimeInterval(windowDuration)
        guard expiration.timeIntervalSinceReferenceDate.isFinite,
              expiration > time.wallClock
        else {
            return unavailable(.persistenceUnavailable)
        }
        let window = SpecialOfferWindow(
            startedAt: time.wallClock,
            expiresAt: expiration
        )
        let state = SpecialOfferState.active(window)
        guard await stateRepository.save(state, for: configuration) else {
            return unavailable(.persistenceUnavailable)
        }
        return SpecialOfferResolution(
            state: state,
            paywall: paywall,
            trustedTime: trustedTime
        )
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

private extension SpecialOfferState {
    var hasTemporalBoundary: Bool {
        switch self {
        case .active, .expired, .cooldown:
            true
        case .unavailable, .eligible:
            false
        }
    }
}
