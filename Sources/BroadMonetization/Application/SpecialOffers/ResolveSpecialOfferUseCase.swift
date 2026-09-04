import BroadCore
import Foundation

private enum StandardSpecialOfferGateOutcome {
    case authorized(PaywallPayload)
    case refused(SpecialOfferResolution)
}

private enum StandardSpecialOfferCadenceOutcome {
    case active(SpecialOfferWindow, SpecialOfferTrustedTime)
    case refused(SpecialOfferResolution)
}

public actor ResolveSpecialOfferUseCase: ResolveSpecialOfferUseCaseProtocol {
    public static let defaultWindowDuration = SpecialOfferConfiguration.standardWindowDuration
    public static let defaultCooldownDuration = SpecialOfferConfiguration.standardCooldownDuration

    private struct InFlightResolution {
        let identifier: UUID
        let configuration: SpecialOfferConfiguration
        let task: Task<SpecialOfferResolution, Never>
    }

    private let loadPaywallUseCase: any LoadPaywallUseCaseProtocol
    private let stateRepository: (any SpecialOfferStateRepositoryProtocol)?
    private let presentationLifecycle: any PaywallPresentationLifecycleProtocol
    private let clock: SpecialOfferClock?
    private let entitlementStatusProvider: (any EntitlementStatusProviderProtocol)?

    private var inFlightResolutions: [PlacementID: InFlightResolution] = [:]

    /// Source-compatible initializer for hosts that have not wired the timed
    /// contract yet. It fails closed when the gate is enabled because a window
    /// cannot be enforced without durable state and trusted time.
    @available(
        *,
        deprecated,
        message: "Inject SpecialOfferStateRepositoryProtocol and SpecialOfferClock"
    )
    public init(
        loadPaywallUseCase: any LoadPaywallUseCaseProtocol,
        presentationLifecycle: any PaywallPresentationLifecycleProtocol
    ) {
        self.loadPaywallUseCase = loadPaywallUseCase
        stateRepository = nil
        self.presentationLifecycle = presentationLifecycle
        clock = nil
        entitlementStatusProvider = nil
    }

    /// Canonical resolver for Maria's fixed 24-hour window and 24-hour cooldown.
    public init(
        loadPaywallUseCase: any LoadPaywallUseCaseProtocol,
        stateRepository: any SpecialOfferStateRepositoryProtocol,
        presentationLifecycle: any PaywallPresentationLifecycleProtocol,
        clock: SpecialOfferClock,
        entitlementStatusProvider: any EntitlementStatusProviderProtocol
    ) {
        self.loadPaywallUseCase = loadPaywallUseCase
        self.stateRepository = stateRepository
        self.presentationLifecycle = presentationLifecycle
        self.clock = clock
        self.entitlementStatusProvider = entitlementStatusProvider
    }

    public func callAsFunction(
        configuration: SpecialOfferConfiguration?
    ) async -> SpecialOfferResolution {
        guard let configuration else {
            return Self.unavailable(.notConfigured)
        }

        while let inFlight = inFlightResolutions[configuration.placementID] {
            _ = await inFlight.task.value
            removeIfCurrent(inFlight, for: configuration.placementID)
        }

        let identifier = UUID()
        let loadPaywallUseCase = loadPaywallUseCase
        let stateRepository = stateRepository
        let presentationLifecycle = presentationLifecycle
        let clock = clock
        let entitlementStatusProvider = entitlementStatusProvider
        let task = Task<SpecialOfferResolution, Never> {
            await Self.resolveConfiguredOffer(
                configuration,
                loadPaywallUseCase: loadPaywallUseCase,
                stateRepository: stateRepository,
                presentationLifecycle: presentationLifecycle,
                clock: clock,
                entitlementStatusProvider: entitlementStatusProvider
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

    /// Clears the running window after a confirmed purchase or restore.
    @discardableResult
    public func resetCycle(
        configuration: SpecialOfferConfiguration
    ) async -> Bool {
        guard let stateRepository else {
            return false
        }
        return await stateRepository.save(.eligible, for: configuration)
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
        stateRepository: (any SpecialOfferStateRepositoryProtocol)?,
        presentationLifecycle: any PaywallPresentationLifecycleProtocol,
        clock: SpecialOfferClock?,
        entitlementStatusProvider: (any EntitlementStatusProviderProtocol)?
    ) async -> SpecialOfferResolution {
        guard let entitlementStatusProvider else { return unavailable(.persistenceUnavailable) }
        guard await entitlementStatusProvider.currentStatus() != .active else {
            return await resetForActiveEntitlement(configuration, stateRepository: stateRepository)
        }
        let gateOutcome = await loadAuthorizedGate(
            configuration,
            loadPaywallUseCase: loadPaywallUseCase,
            stateRepository: stateRepository,
            presentationLifecycle: presentationLifecycle
        )
        guard case let .authorized(gatePaywall) = gateOutcome else {
            guard case let .refused(resolution) = gateOutcome else { preconditionFailure() }
            return resolution
        }
        let cadenceOutcome = await authorizeCadence(
            configuration,
            stateRepository: stateRepository,
            clock: clock
        )
        guard case let .active(window, trustedTime) = cadenceOutcome else {
            await end(gatePaywall, using: presentationLifecycle)
            guard case let .refused(resolution) = cadenceOutcome else { preconditionFailure() }
            return resolution
        }
        guard let offerPaywall = await loadAuthorizedOffer(
            configuration,
            loadPaywallUseCase: loadPaywallUseCase,
            presentationLifecycle: presentationLifecycle
        ) else {
            await end(gatePaywall, using: presentationLifecycle)
            return unavailable(.paywallUnavailable)
        }
        let resolution = SpecialOfferResolution(
            state: .active(window),
            paywall: offerPaywall,
            trustedTime: trustedTime,
            gatePaywall: gatePaywall
        )
        await end(gatePaywall, using: presentationLifecycle)
        return resolution
    }

    static func resetForActiveEntitlement(
        _ configuration: SpecialOfferConfiguration,
        stateRepository: (any SpecialOfferStateRepositoryProtocol)?
    ) async -> SpecialOfferResolution {
        guard await resetIfPossible(configuration, stateRepository: stateRepository) else {
            return unavailable(.persistenceUnavailable)
        }
        return unavailable(.alreadyEntitled)
    }

    static func loadAuthorizedGate(
        _ configuration: SpecialOfferConfiguration,
        loadPaywallUseCase: any LoadPaywallUseCaseProtocol,
        stateRepository: (any SpecialOfferStateRepositoryProtocol)?,
        presentationLifecycle: any PaywallPresentationLifecycleProtocol
    ) async -> StandardSpecialOfferGateOutcome {
        let outcome = await loadPaywallUseCase(
            PaywallLoadRequest(placementID: configuration.gatePlacementID)
        )
        guard case let .loaded(paywall) = outcome else {
            return .refused(unavailable(.paywallUnavailable))
        }
        guard isExactOrigin(paywall.origin, placementID: configuration.gatePlacementID) else {
            await end(paywall, using: presentationLifecycle)
            return .refused(unavailable(.paywallUnavailable))
        }
        guard paywall.remoteConfigurationProvenance.authorizesSpecialOfferPresentation,
              paywall.remoteConfiguration.specialOffer?.isEnabled == true
        else {
            await end(paywall, using: presentationLifecycle)
            guard await resetIfPossible(configuration, stateRepository: stateRepository) else {
                return .refused(unavailable(.persistenceUnavailable))
            }
            return .refused(unavailable(.disabledByRemoteConfiguration))
        }
        return .authorized(paywall)
    }

    static func authorizeCadence(
        _ configuration: SpecialOfferConfiguration,
        stateRepository: (any SpecialOfferStateRepositoryProtocol)?,
        clock: SpecialOfferClock?
    ) async -> StandardSpecialOfferCadenceOutcome {
        guard let stateRepository else {
            return .refused(unavailable(.persistenceUnavailable))
        }
        guard let clock, case let .synchronized(time) = await clock.reading() else {
            return .refused(unavailable(.untrustedTime))
        }
        guard case let .loaded(state) = await stateRepository.state(for: configuration) else {
            return .refused(unavailable(.persistenceUnavailable))
        }
        let nextState = nextState(from: state, now: time.date)
        guard await stateRepository.save(nextState, for: configuration) else {
            return .refused(unavailable(.persistenceUnavailable))
        }
        if case let .active(window) = nextState {
            return .active(window, time)
        }
        if case let .cooldown(until) = nextState {
            return .refused(SpecialOfferResolution(state: .cooldown(until: until), paywall: nil))
        }
        return .refused(unavailable(.ineligible))
    }

    static func loadAuthorizedOffer(
        _ configuration: SpecialOfferConfiguration,
        loadPaywallUseCase: any LoadPaywallUseCaseProtocol,
        presentationLifecycle: any PaywallPresentationLifecycleProtocol
    ) async -> PaywallPayload? {
        let outcome = await loadPaywallUseCase(
            PaywallLoadRequest(placementID: configuration.placementID)
        )
        guard case let .loaded(paywall) = outcome else { return nil }
        guard isExactOrigin(paywall.origin, placementID: configuration.placementID),
              paywall.remoteConfigurationProvenance.authorizesSpecialOfferPresentation,
              !paywall.products.isEmpty
        else {
            await end(paywall, using: presentationLifecycle)
            return nil
        }
        return paywall
    }

    /// The cadence is continuous after the first qualifying close: every
    /// 24-hour active phase is followed immediately by a 24-hour cooldown, even
    /// while the app is not running.
    static func nextState(
        from state: SpecialOfferState,
        now: Date
    ) -> SpecialOfferState {
        switch state {
        case let .active(window):
            return phase(
                startingAt: window.startedAt,
                now: now
            )
        case let .cooldown(until):
            if now < until {
                return .cooldown(until: until)
            }
            return phase(startingAt: until, now: now)
        case .eligible, .expired, .unavailable:
            return .active(newWindow(startingAt: now))
        }
    }

    static func phase(
        startingAt initialWindowStart: Date,
        now: Date
    ) -> SpecialOfferState {
        let windowDuration = defaultWindowDuration
        let cooldownDuration = defaultCooldownDuration
        let fullCycleDuration = windowDuration + cooldownDuration
        let elapsed = max(0, now.timeIntervalSince(initialWindowStart))
        let completedCycles = floor(elapsed / fullCycleDuration)
        let cycleStart = initialWindowStart.addingTimeInterval(
            completedCycles * fullCycleDuration
        )
        let activeUntil = cycleStart.addingTimeInterval(windowDuration)
        if now < activeUntil {
            return .active(
                SpecialOfferWindow(startedAt: cycleStart, expiresAt: activeUntil)
            )
        }
        return .cooldown(
            until: cycleStart.addingTimeInterval(fullCycleDuration)
        )
    }

    static func newWindow(
        startingAt date: Date
    ) -> SpecialOfferWindow {
        SpecialOfferWindow(
            startedAt: date,
            expiresAt: date.addingTimeInterval(defaultWindowDuration)
        )
    }

    static func isExactOrigin(
        _ origin: PaywallOrigin,
        placementID: PlacementID
    ) -> Bool {
        !origin.usedFallback
            && origin.requestedPlacementID == placementID
            && origin.resolvedPlacementID == placementID
    }

    static func resetIfPossible(
        _ configuration: SpecialOfferConfiguration,
        stateRepository: (any SpecialOfferStateRepositoryProtocol)?
    ) async -> Bool {
        guard let stateRepository else {
            return true
        }
        return await stateRepository.save(.eligible, for: configuration)
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
