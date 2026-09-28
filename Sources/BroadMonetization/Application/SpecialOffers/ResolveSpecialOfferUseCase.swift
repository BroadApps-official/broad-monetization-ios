import BroadCore
import Foundation

enum StandardSpecialOfferGateOutcome {
    case authorized(PaywallPayload)
    case refused(SpecialOfferResolution)
}

enum StandardSpecialOfferCadenceOutcome {
    case active(SpecialOfferWindow, SpecialOfferTrustedTime)
    case refused(SpecialOfferResolution)
}

public actor ResolveSpecialOfferUseCase: ResolveSpecialOfferUseCaseProtocol {
    public static let defaultWindowDuration = SpecialOfferConfiguration.standardWindowDuration
    public static let defaultCooldownDuration = SpecialOfferConfiguration.standardCooldownDuration
    static let preparationLifetime: Duration = .seconds(600)

    private struct InFlightResolution {
        let identifier: UUID
        let configuration: SpecialOfferConfiguration
        let task: Task<SpecialOfferResolution, Never>
    }

    let loadPaywallUseCase: any LoadPaywallUseCaseProtocol
    let stateRepository: (any SpecialOfferStateRepositoryProtocol)?
    let presentationLifecycle: any PaywallPresentationLifecycleProtocol
    private let clock: SpecialOfferClock?
    let entitlementStatusProvider: (any EntitlementStatusProviderProtocol)?

    private var inFlightResolutions: [PlacementID: InFlightResolution] = [:]
    var preparedOffer: PreparedOffer?
    var preparationGeneration: UInt64 = 0

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

        preparationGeneration &+= 1
        let preparation = preparedOffer
        preparedOffer = nil
        let identifier = UUID()
        let loadPaywallUseCase = loadPaywallUseCase
        let stateRepository = stateRepository
        let presentationLifecycle = presentationLifecycle
        let clock = clock
        let entitlementStatusProvider = entitlementStatusProvider
        let task = Task<SpecialOfferResolution, Never> {
            let usablePreparation = preparation?.isFresh(for: configuration) == true
                ? preparation : nil
            if let preparation, usablePreparation == nil {
                await Self.end(preparation, using: presentationLifecycle)
            }
            return await Self.resolveConfiguredOffer(
                configuration,
                preparedOffer: usablePreparation,
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
}

extension ResolveSpecialOfferUseCase {
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
        preparedOffer: PreparedOffer?,
        loadPaywallUseCase: any LoadPaywallUseCaseProtocol,
        stateRepository: (any SpecialOfferStateRepositoryProtocol)?,
        presentationLifecycle: any PaywallPresentationLifecycleProtocol,
        clock: SpecialOfferClock?,
        entitlementStatusProvider: (any EntitlementStatusProviderProtocol)?
    ) async -> SpecialOfferResolution {
        guard let entitlementStatusProvider else {
            if let preparedOffer {
                await end(preparedOffer, using: presentationLifecycle)
            }
            return unavailable(.persistenceUnavailable)
        }
        guard await entitlementStatusProvider.currentStatus() != .active else {
            if let preparedOffer {
                await end(preparedOffer, using: presentationLifecycle)
            }
            return await resetForActiveEntitlement(configuration, stateRepository: stateRepository)
        }
        if let preparedOffer {
            return await resolvePreparedOffer(
                configuration,
                preparation: preparedOffer,
                stateRepository: stateRepository,
                presentationLifecycle: presentationLifecycle,
                clock: clock
            )
        }
        return await resolveUnpreparedOffer(
            configuration,
            loadPaywallUseCase: loadPaywallUseCase,
            stateRepository: stateRepository,
            presentationLifecycle: presentationLifecycle,
            clock: clock
        )
    }

    static func resolvePreparedOffer(
        _ configuration: SpecialOfferConfiguration,
        preparation: PreparedOffer,
        stateRepository: (any SpecialOfferStateRepositoryProtocol)?,
        presentationLifecycle: any PaywallPresentationLifecycleProtocol,
        clock: SpecialOfferClock?
    ) async -> SpecialOfferResolution {
        let cadenceOutcome = await authorizeCadence(
            configuration,
            stateRepository: stateRepository,
            clock: clock
        )
        guard case let .active(window, trustedTime) = cadenceOutcome else {
            await end(preparation, using: presentationLifecycle)
            guard case let .refused(resolution) = cadenceOutcome else { preconditionFailure() }
            return resolution
        }
        guard preparation.gatePaywall.remoteConfigurationProvenance
            .authorizesSpecialOfferPresentation,
            preparation.gatePaywall.remoteConfiguration.specialOffer?.isEnabled == true,
            preparation.offerPaywall.remoteConfigurationProvenance
            .authorizesSpecialOfferPresentation,
            preparation.offerPaywall.remoteConfiguration.specialOffer?.isEnabled == true
        else {
            await end(preparation, using: presentationLifecycle)
            guard await resetIfPossible(configuration, stateRepository: stateRepository) else {
                return unavailable(.persistenceUnavailable)
            }
            return unavailable(.disabledByRemoteConfiguration)
        }
        await end(preparation.gatePaywall, using: presentationLifecycle)
        return SpecialOfferResolution(
            state: .active(window),
            paywall: preparation.offerPaywall,
            trustedTime: trustedTime,
            gatePaywall: preparation.gatePaywall
        )
    }

    static func resolveUnpreparedOffer(
        _ configuration: SpecialOfferConfiguration,
        loadPaywallUseCase: any LoadPaywallUseCaseProtocol,
        stateRepository: (any SpecialOfferStateRepositoryProtocol)?,
        presentationLifecycle: any PaywallPresentationLifecycleProtocol,
        clock: SpecialOfferClock?
    ) async -> SpecialOfferResolution {
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
        // Loading the offer resolves its own configuration. Its prohibition must
        // revoke the earlier gate before the separate offer can be presented.
        guard offerPaywall.remoteConfiguration.specialOffer?.isEnabled == true else {
            await end(offerPaywall, using: presentationLifecycle)
            await end(gatePaywall, using: presentationLifecycle)
            guard await resetIfPossible(configuration, stateRepository: stateRepository) else {
                return unavailable(.persistenceUnavailable)
            }
            return unavailable(.disabledByRemoteConfiguration)
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
        presentationLifecycle: any PaywallPresentationLifecycleProtocol,
        resetOnDisabled: Bool = true
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
            if resetOnDisabled {
                guard await resetIfPossible(configuration, stateRepository: stateRepository) else {
                    return .refused(unavailable(.persistenceUnavailable))
                }
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
