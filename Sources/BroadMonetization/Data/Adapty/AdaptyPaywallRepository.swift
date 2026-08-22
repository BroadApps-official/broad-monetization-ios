import Adapty
import BroadCore
import Foundation

public actor AdaptyPaywallRepository:
    PaywallRepositoryProtocol,
    RemoteConfigRepositoryProtocol {
    private let configuration: AdaptyPlatformConfiguration
    private let identityProvider: any AdaptyIdentityProviderProtocol
    private let placementRegistry: AdaptyPlacementRegistry
    private let context: AdaptyRepositoryContext
    private let remoteConfigurationParser: RemotePaywallConfigurationParser
    private let remoteConfigurationStore: LastValidRemoteConfigurationStore
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
        self.remoteConfigurationStore = remoteConfigurationStore
        self.messages = messages
        self.clock = clock
        self.retainedConfigurationLimit = retainedConfigurationLimit
    }

    public func loadPaywall(
        for placementID: PlacementID
    ) async -> PaywallLoadOutcome {
        guard let adaptyPlacementID = placementRegistry.adaptyPlacement(for: placementID) else {
            return unavailable(code: "monetization.paywall.placement-not-configured")
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
                    await loadAdaptyPaywall(
                        adaptyPlacementID: adaptyPlacementID,
                        logicalPlacementID: placementID
                    )
                }
            )
            return outcome ?? unavailable(code: "monetization.paywall.activation-unavailable")
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
        let task: Task<PaywallLoadOutcome, Never>
        var pendingDeliveries: Int
    }

    func awaitLoad(
        _ inFlightLoad: InFlightLoad,
        for placementID: PlacementID,
        requiresUniquePresentation: Bool
    ) async -> PaywallLoadOutcome {
        let outcome = await inFlightLoad.task.value
        let deliveredOutcome = await prepareDelivery(
            outcome,
            requiresUniquePresentation: requiresUniquePresentation
        )
        await finishDelivery(
            inFlightLoad,
            for: placementID,
            outcome: outcome
        )
        return deliveredOutcome
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

    func loadAdaptyPaywall(
        adaptyPlacementID: AdaptyPlacementID,
        logicalPlacementID: PlacementID
    ) async -> PaywallLoadOutcome {
        do {
            let paywall = try await Adapty.getPaywall(
                placementId: adaptyPlacementID.rawValue,
                fetchPolicy: .reloadRevalidatingCacheData,
                loadTimeout: configuration.paywallLoadTimeout
            )

            let adaptyProducts = try await Adapty.getPaywallProducts(paywall: paywall)

            let presentationID = PaywallPresentationID.generated()
            let paywallReference = PaywallReference.generatedForAdapty()
            let mappedProducts = Self.mapProducts(adaptyProducts)
            let parsedConfiguration = remoteConfigurationParser.parse(
                paywall.remoteConfig?.dictionary ?? [:]
            )
            let remoteConfiguration = await remoteConfigurationStore.resolve(
                parsedConfiguration,
                for: logicalPlacementID
            )

            return await .loaded(
                registerPayload(
                    paywall: paywall,
                    paywallReference: paywallReference,
                    presentationID: presentationID,
                    logicalPlacementID: logicalPlacementID,
                    mappedProducts: mappedProducts,
                    adaptyProducts: adaptyProducts,
                    remoteConfiguration: remoteConfiguration
                )
            )
        } catch {
            return unavailable(code: "monetization.paywall.load-unavailable")
        }
    }

    func registerPayload(
        paywall: AdaptyPaywall,
        paywallReference: PaywallReference,
        presentationID: PaywallPresentationID,
        logicalPlacementID: PlacementID,
        mappedProducts: [MonetizationProduct],
        adaptyProducts: [any AdaptyPaywallProduct],
        remoteConfiguration: RemotePaywallConfiguration
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
            // Adapty owns the current payload and may transparently satisfy the
            // request from its managed cache. This provenance authorizes
            // provider feature gates, but never proves a financial entitlement.
            remoteConfigurationProvenance: .providerCacheFallbackPossible,
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
