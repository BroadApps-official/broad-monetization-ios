import BroadCore
import Foundation

extension ResolveSpecialOfferUseCase {
    struct PreparedOffer {
        let configuration: SpecialOfferConfiguration
        let gatePaywall: PaywallPayload
        let offerPaywall: PaywallPayload
        let expiresAt: ContinuousClock.Instant

        func isFresh(for configuration: SpecialOfferConfiguration) -> Bool {
            self.configuration == configuration && ContinuousClock().now < expiresAt
        }
    }

    /// Preloads the strict ordinary-paywall gate and all offer products. The
    /// 24-hour window starts only when `callAsFunction(configuration:)` runs.
    public func prepare(configuration: SpecialOfferConfiguration) async {
        preparationGeneration &+= 1
        let generation = preparationGeneration
        let previous = preparedOffer
        preparedOffer = nil
        if let previous {
            await Self.end(previous, using: presentationLifecycle)
        }
        guard generation == preparationGeneration,
              let entitlementStatusProvider,
              await entitlementStatusProvider.currentStatus() != .active
        else { return }

        let gateOutcome = await Self.loadAuthorizedGate(
            configuration,
            loadPaywallUseCase: loadPaywallUseCase,
            stateRepository: stateRepository,
            presentationLifecycle: presentationLifecycle,
            resetOnDisabled: false
        )
        guard case let .authorized(gatePaywall) = gateOutcome else { return }
        await finishPreparation(
            configuration,
            gatePaywall: gatePaywall,
            generation: generation,
            entitlementStatusProvider: entitlementStatusProvider
        )
    }

    /// Clears the running window after a confirmed purchase or restore.
    @discardableResult
    public func resetCycle(
        configuration: SpecialOfferConfiguration
    ) async -> Bool {
        preparationGeneration &+= 1
        let previous = preparedOffer
        preparedOffer = nil
        if let previous {
            await Self.end(previous, using: presentationLifecycle)
        }
        guard let stateRepository else {
            return false
        }
        return await stateRepository.save(.eligible, for: configuration)
    }

    private func finishPreparation(
        _ configuration: SpecialOfferConfiguration,
        gatePaywall: PaywallPayload,
        generation: UInt64,
        entitlementStatusProvider: any EntitlementStatusProviderProtocol
    ) async {
        guard generation == preparationGeneration, !Task.isCancelled else {
            await Self.end(gatePaywall, using: presentationLifecycle)
            return
        }
        guard let offerPaywall = await Self.loadAuthorizedOffer(
            configuration,
            loadPaywallUseCase: loadPaywallUseCase,
            presentationLifecycle: presentationLifecycle
        ) else {
            await Self.end(gatePaywall, using: presentationLifecycle)
            return
        }
        guard generation == preparationGeneration,
              !Task.isCancelled,
              offerPaywall.remoteConfiguration.specialOffer?.isEnabled == true,
              await entitlementStatusProvider.currentStatus() != .active
        else {
            await Self.end(gatePaywall, using: presentationLifecycle)
            await Self.end(offerPaywall, using: presentationLifecycle)
            return
        }
        guard generation == preparationGeneration else {
            await Self.end(gatePaywall, using: presentationLifecycle)
            await Self.end(offerPaywall, using: presentationLifecycle)
            return
        }
        preparedOffer = PreparedOffer(
            configuration: configuration,
            gatePaywall: gatePaywall,
            offerPaywall: offerPaywall,
            expiresAt: ContinuousClock().now.advanced(by: Self.preparationLifetime)
        )
        Task { [generation] in
            try? await Task.sleep(for: Self.preparationLifetime)
            await expirePreparation(generation: generation)
        }
    }

    private func expirePreparation(generation: UInt64) async {
        guard generation == preparationGeneration,
              let preparation = preparedOffer,
              ContinuousClock().now >= preparation.expiresAt
        else { return }
        preparedOffer = nil
        preparationGeneration &+= 1
        await Self.end(preparation, using: presentationLifecycle)
    }

    static func end(
        _ preparation: PreparedOffer,
        using lifecycle: any PaywallPresentationLifecycleProtocol
    ) async {
        await end(preparation.gatePaywall, using: lifecycle)
        await end(preparation.offerPaywall, using: lifecycle)
    }
}
