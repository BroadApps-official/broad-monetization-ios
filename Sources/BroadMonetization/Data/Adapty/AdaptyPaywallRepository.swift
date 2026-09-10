import Adapty
import BroadCore
import Foundation

public actor AdaptyPaywallRepository:
    RUFallbackPaywallRepositoryProtocol,
    RemoteConfigRepositoryProtocol {
    private let configuration: AdaptyPlatformConfiguration
    private let identityProvider: any AdaptyIdentityProviderProtocol
    private let placementRegistry: AdaptyPlacementRegistry
    private let context: AdaptyRepositoryContext
    private let remoteConfigurationParser: RemotePaywallConfigurationParser
    private let placementConfigurationLoader: PlacementPaywallConfigurationLoader<AdaptyPaywall>
    private let messages: AdaptyMonetizationMessages
    private let clock: CacheClock
    private let retainedConfigurationLimit: Int

    private var loadSequence: UInt64 = 0
    private var inFlightLoads: [PlacementID: InFlightLoad] = [:]
    private var configurations: [PaywallReference: RemotePaywallConfiguration] = [:]
    private var configurationOrder: [PaywallReference] = []

    public init(
        configuration: AdaptyPlatformConfiguration,
        identityProvider: any AdaptyIdentityProviderProtocol,
        placementRegistry: AdaptyPlacementRegistry,
        context: AdaptyRepositoryContext,
        remoteConfigurationParser: RemotePaywallConfigurationParser = .init(),
        remoteConfigurationStore: LastValidRemoteConfigurationStore = .init(),
        messages: AdaptyMonetizationMessages,
        clock: CacheClock = .system,
        retainedConfigurationLimit: Int = 32
    ) {
        precondition(
            retainedConfigurationLimit > 0,
            "Retained remote configuration limit must be positive"
        )
        self.configuration = configuration
        self.identityProvider = identityProvider
        self.placementRegistry = placementRegistry
        self.context = context
        self.remoteConfigurationParser = remoteConfigurationParser
        placementConfigurationLoader = PlacementPaywallConfigurationLoader(store: remoteConfigurationStore)
        self.messages = messages
        self.clock = clock
        self.retainedConfigurationLimit = retainedConfigurationLimit
    }

    public func loadPaywall(
        for placementID: PlacementID
    ) async -> PaywallLoadOutcome {
        await loadRUFallbackAttempt(for: placementID).outcome
    }

    public func loadRUFallbackAttempt(
        for placementID: PlacementID
    ) async -> RUFallbackPaywallAttempt {
        guard placementRegistry.contains(placementID) else {
            return RUFallbackPaywallAttempt(
                outcome: unavailable(code: "monetization.paywall.placement-not-configured"),
                availability: .notConfigured
            )
        }

        if var inFlightLoad = inFlightLoads[placementID] {
            inFlightLoad.pendingDeliveries += 1
            inFlightLoads[placementID] = inFlightLoad
            return await awaitLoad(
                inFlightLoad,
                for: placementID,
                requiresUniquePresentation: true
            )
        }

        loadSequence &+= 1
        let loadToken = loadSequence
        let task = Task { [self] in
            let outcome = await AdaptySDKActivationGate.shared.perform(
                configuration: configuration,
                identityProvider: identityProvider,
                compositionID: context.sdkCompositionID,
                operation: { [self] in
                    await loadAdaptyPaywall(logicalPlacementID: placementID)
                }
            )
            return outcome ?? RUFallbackPaywallAttempt(
                outcome: unavailable(code: "monetization.paywall.activation-unavailable"),
                availability: .unavailable(receivedConfiguration: nil)
            )
        }
        let inFlightLoad = InFlightLoad(
            token: loadToken,
            task: task,
            pendingDeliveries: 1
        )
        inFlightLoads[placementID] = inFlightLoad
        return await awaitLoad(
            inFlightLoad,
            for: placementID,
            requiresUniquePresentation: false
        )
    }

    public func configuration(
        for paywallReference: PaywallReference
    ) async -> RemoteConfigurationLoadOutcome {
        guard let configuration = configurations[paywallReference] else {
            return .missing
        }
        return .loaded(configuration)
    }
}

private extension AdaptyPaywallRepository {
    struct InFlightLoad {
        let token: UInt64
        let task: Task<RUFallbackPaywallAttempt, Never>
        var pendingDeliveries: Int
    }

    func awaitLoad(
        _ inFlightLoad: InFlightLoad,
        for placementID: PlacementID,
        requiresUniquePresentation: Bool
    ) async -> RUFallbackPaywallAttempt {
        let attempt = await inFlightLoad.task.value
        let outcome = attempt.outcome
        let deliveredOutcome = await prepareDelivery(
            outcome,
            requiresUniquePresentation: requiresUniquePresentation
        )
        await finishDelivery(
            inFlightLoad,
            for: placementID,
            outcome: outcome
        )
        return RUFallbackPaywallAttempt(outcome: deliveredOutcome, availability: attempt.availability)
    }

    func prepareDelivery(
        _ outcome: PaywallLoadOutcome,
        requiresUniquePresentation: Bool
    ) async -> PaywallLoadOutcome {
        guard !Task.isCancelled else {
            if !requiresUniquePresentation, case let .loaded(paywall) = outcome {
                await releasePresentation(paywall)
            }
            return unavailable(code: "monetization.paywall.load-cancelled")
        }
        guard requiresUniquePresentation,
              case let .loaded(paywall) = outcome
        else {
            return outcome
        }

        let uniquePaywall = paywall.preparedForNewPresentation()
        guard await context.productRegistry.clonePresentation(
            from: paywall.presentationID,
            reference: paywall.paywallReference,
            to: uniquePaywall.presentationID
        ) else {
            return unavailable(code: "monetization.paywall.presentation-unavailable")
        }

        guard !Task.isCancelled else {
            await releasePresentation(uniquePaywall)
            return unavailable(code: "monetization.paywall.load-cancelled")
        }
        return .loaded(uniquePaywall)
    }

    func finishDelivery(
        _ inFlightLoad: InFlightLoad,
        for placementID: PlacementID,
        outcome: PaywallLoadOutcome
    ) async {
        guard var currentLoad = inFlightLoads[placementID],
              currentLoad.token == inFlightLoad.token
        else {
            return
        }

        precondition(currentLoad.pendingDeliveries > 0, "In-flight delivery count underflow")
        currentLoad.pendingDeliveries -= 1
        guard currentLoad.pendingDeliveries == 0 else {
            inFlightLoads[placementID] = currentLoad
            return
        }

        inFlightLoads.removeValue(forKey: placementID)
        guard case let .loaded(sourcePaywall) = outcome else {
            return
        }
        await context.productRegistry.endCohortRetention(
            presentationID: sourcePaywall.presentationID,
            reference: sourcePaywall.paywallReference
        )
    }

    func releasePresentation(
        _ paywall: PaywallPayload
    ) async {
        await context.productRegistry.release(
            presentationID: paywall.presentationID,
            reference: paywall.paywallReference
        )
    }

    func fetchAdaptyPaywall(for placementID: PlacementID) async -> AdaptyPaywall? {
        let timeout = configuration.paywallLoadTimeout
        return await placementRegistry.loadPaywall(for: placementID) { candidate in
            try? await Adapty.getPaywall(
                placementId: candidate.rawValue,
                fetchPolicy: .reloadRevalidatingCacheData,
                loadTimeout: timeout
            )
        }
    }

    func loadAdaptyPaywall(logicalPlacementID: PlacementID) async -> RUFallbackPaywallAttempt {
        let parser = remoteConfigurationParser
        let source = await placementConfigurationLoader.load(
            for: logicalPlacementID,
            fetch: { [self] in await fetchAdaptyPaywall(for: $0) },
            parse: { paywall, main in
                parser.parse(paywall.remoteConfig?.dictionary ?? [:], fallback: main?.remoteConfig?.dictionary ?? [:])
            }
        )
        // Preserve the selected placement's decision if products loading fails.
        let receivedConfiguration = source.remoteConfiguration
        guard let paywall = source.paywall else {
            return RUFallbackPaywallAttempt(
                outcome: unavailable(code: "monetization.paywall.load-unavailable"),
                availability: .unavailable(receivedConfiguration: receivedConfiguration)
            )
        }
        do {
            let adaptyProducts = try await Adapty.getPaywallProducts(paywall: paywall)
            let presentationID = PaywallPresentationID.generated()
            let paywallReference = PaywallReference.generatedForAdapty()
            let mappedProducts = Self.mapProducts(adaptyProducts)

            let payload = await registerPayload(
                paywall: paywall,
                paywallReference: paywallReference,
                presentationID: presentationID,
                logicalPlacementID: logicalPlacementID,
                mappedProducts: mappedProducts,
                adaptyProducts: adaptyProducts,
                remoteConfiguration: receivedConfiguration ?? .empty,
                remoteConfigurationProvenance: receivedConfiguration == nil
                    ? .legacyUnqualified : .providerCacheFallbackPossible
            )
            return RUFallbackPaywallAttempt(
                outcome: .loaded(payload),
                availability: mappedProducts.isEmpty
                    ? .unavailable(receivedConfiguration: receivedConfiguration)
                    : .available
            )
        } catch {
            return RUFallbackPaywallAttempt(
                outcome: unavailable(code: "monetization.paywall.load-unavailable"),
                availability: .unavailable(receivedConfiguration: receivedConfiguration)
            )
        }
    }

    func registerPayload(
        paywall: AdaptyPaywall,
        paywallReference: PaywallReference,
        presentationID: PaywallPresentationID,
        logicalPlacementID: PlacementID,
        mappedProducts: [MonetizationProduct],
        adaptyProducts: [any AdaptyPaywallProduct],
        remoteConfiguration: RemotePaywallConfiguration,
        remoteConfigurationProvenance: PaywallRemoteConfigurationProvenance
    ) async -> PaywallPayload {
        await context.productRegistry.store(
            paywall: paywall,
            paywallReference: paywallReference,
            presentationID: presentationID,
            products: zip(mappedProducts, adaptyProducts).map { mappedProduct, adaptyProduct in
                (mappedProduct.reference, adaptyProduct)
            },
            retainedForCohort: true
        )
        storeConfiguration(remoteConfiguration, for: paywallReference)

        return PaywallPayload(
            presentationID: presentationID,
            paywallReference: paywallReference,
            variationID: PaywallVariationID.optional(paywall.variationId),
            origin: PaywallOrigin(
                requestedPlacementID: logicalPlacementID,
                resolvedPlacementID: logicalPlacementID,
                catalogSource: .adapty
            ),
            products: mappedProducts,
            remoteConfiguration: remoteConfiguration,
            // Both configuration sources are current SDK responses, which can
            // include provider cache and cannot prove RU freshness.
            remoteConfigurationProvenance: remoteConfigurationProvenance,
            fetchedAt: clock.now()
        )
    }

    func unavailable(code: String) -> PaywallLoadOutcome {
        .unavailable(
            AppError(
                kind: .unavailable,
                userMessage: messages.paywallUnavailable,
                diagnosticCode: code,
                isRetryable: true
            )
        )
    }

    func storeConfiguration(
        _ configuration: RemotePaywallConfiguration,
        for reference: PaywallReference
    ) {
        configurations[reference] = configuration
        configurationOrder.removeAll { $0 == reference }
        configurationOrder.append(reference)

        while configurationOrder.count > retainedConfigurationLimit {
            let removedReference = configurationOrder.removeFirst()
            configurations.removeValue(forKey: removedReference)
        }
    }
}

private extension PaywallReference {
    static func generatedForAdapty() -> PaywallReference {
        PaywallReference(rawValue: "adapty-\(UUID().uuidString.lowercased())")
    }
}

private extension PaywallVariationID {
    static func optional(_ rawValue: String) -> PaywallVariationID? {
        guard MonetizationIdentifierPolicy.isValid(rawValue) else {
            return nil
        }
        return PaywallVariationID(rawValue: rawValue)
    }
}
