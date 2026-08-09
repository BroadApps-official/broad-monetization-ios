import BroadCore
import Foundation

public actor EntitlementEngine:
    EntitlementRepositoryProtocol,
    EntitlementStatusProviderProtocol,
    RefreshEntitlementUseCaseProtocol {
    private let registrations: [EntitlementSourceRuntime]
    private let subject: EntitlementSubject
    private let timeoutPolicy: TimeoutPolicy
    private let clock: CacheClock
    private let aggregator: EntitlementAggregator
    private let cacheReaders: [EntitlementSource: EntitlementCacheReader]
    private let cacheScopes: [EntitlementSource: EntitlementCacheScope]
    private let cachePersistence: EntitlementCachePersistenceCoordinator
    private let analytics: any MonetizationAnalyticsProtocol

    private var generation: UInt64 = 0
    private var inFlight: InFlight?
    private var acceptedGeneration: UInt64?
    private var sessionAssertions: [EntitlementSource: EntitlementSourceAssertion] = [:]
    private var latestObservations: [EntitlementSourceObservation]?

    public init(
        registrations: [EntitlementSourceRegistration],
        subject: EntitlementSubject,
        cache: any EntitlementCacheProtocol,
        timeoutPolicy: TimeoutPolicy,
        clock: CacheClock = .system,
        aggregator: EntitlementAggregator = EntitlementAggregator(),
        analytics: any MonetizationAnalyticsProtocol = NoOpMonetizationAnalytics()
    ) {
        precondition(
            Set(registrations.map(\.source)).count == registrations.count,
            "Entitlement registrations must have unique logical sources"
        )
        precondition(
            registrations.allSatisfy { $0.subject == subject },
            "Entitlement registrations and engine must use the same subject"
        )

        self.registrations = registrations.map {
            EntitlementSourceRuntime(registration: $0)
        }
        self.subject = subject
        self.timeoutPolicy = timeoutPolicy
        self.clock = clock
        self.aggregator = aggregator
        self.analytics = NonBlockingMonetizationAnalytics.wrapping(analytics)
        let resolvedCacheScopes = Dictionary(
            uniqueKeysWithValues: registrations.map { registration in
                let scope = EntitlementCacheScope(
                    source: registration.source,
                    subject: subject,
                    partition: registration.acceptanceGate.cachePartition,
                    storagePartition: registration.acceptanceGate.cacheStoragePartition
                )
                return (registration.source, scope)
            }
        )
        cacheScopes = resolvedCacheScopes
        cacheReaders = resolvedCacheScopes.mapValues { scope in
            EntitlementCacheReader(
                gate: EntitlementCacheReadGate(
                    cache: cache,
                    scope: scope
                )
            )
        }
        cachePersistence = EntitlementCachePersistenceCoordinator(cache: cache)
    }

    public func refreshEntitlement(
        policy: EntitlementRefreshPolicy
    ) async -> EntitlementSnapshot {
        discardSessionAssertionsForInvalidContexts()

        if policy == .joinInFlight, let inFlight {
            return await value(of: inFlight)
        }

        if policy == .startNewGeneration {
            inFlight?.task.cancel()
        }

        generation &+= 1
        let currentGeneration = generation
        let registrations = registrations
        let timeoutPolicy = timeoutPolicy
        let clock = clock
        let aggregator = aggregator
        let cacheReaders = cacheReaders
        let sessionAssertions = sessionAssertions
        let task = Task {
            await EntitlementRefreshExecutor.perform(
                registrations: registrations,
                timeoutPolicy: timeoutPolicy,
                clock: clock,
                aggregator: aggregator,
                cacheReaders: cacheReaders,
                sessionAssertions: sessionAssertions,
                refreshPolicy: policy,
                refreshGeneration: currentGeneration
            )
        }
        let execution = InFlight(
            generation: currentGeneration,
            analyticsAttemptID: .generated(),
            task: task
        )
        inFlight = execution

        return await value(of: execution)
    }

    public func latestEntitlement() -> EntitlementSnapshot? {
        guard let latestObservations else {
            return nil
        }

        let observations = acceptedObservations(
            latestObservations.map { observation in
                EntitlementSourceObservation(
                    source: observation.source,
                    freshnessPolicy: observation.freshnessPolicy,
                    assertion: observation.assertion,
                    isFromCurrentRefresh: false
                )
            }
        )
        return aggregator.resolve(
            observations: observations,
            now: clock.now()
        )
    }

    public func callAsFunction(
        policy: EntitlementRefreshPolicy
    ) async -> EntitlementSnapshot {
        await refreshEntitlement(policy: policy)
    }
}

private extension EntitlementEngine {
    struct InFlight {
        let generation: UInt64
        let analyticsAttemptID: MonetizationAttemptID
        let task: Task<EntitlementRefreshOutput, Never>
    }

    func value(
        of initialExecution: InFlight
    ) async -> EntitlementSnapshot {
        var execution = initialExecution

        while true {
            let output = await acceptedOutput(execution.task.value)

            guard let currentExecution = inFlight else {
                if acceptedGeneration == execution.generation {
                    return output.snapshot
                }
                return latestEntitlement()
                    ?? output.snapshot
            }

            guard currentExecution.generation == execution.generation else {
                execution = currentExecution
                continue
            }

            for (source, assertion) in output.refreshedAssertions {
                sessionAssertions[source] = assertion
            }
            latestObservations = output.observations
            acceptedGeneration = execution.generation
            inFlight = nil
            await cachePersistence.schedule(
                assertions: output.refreshedAssertions,
                scopes: cacheScopes,
                generation: execution.generation
            )
            let analyticsOutput = acceptedOutput(output)
            await analytics.track(
                .entitlementResolved(
                    EntitlementAnalyticsContext(
                        attemptID: execution.analyticsAttemptID,
                        snapshot: analyticsOutput.snapshot
                    )
                )
            )

            // Both calls above cross actor boundaries. Authorization can be
            // revoked while either suspension is in progress, so publication
            // must use a fresh acceptance check after the final await.
            let finalOutput = acceptedOutput(output)
            discardSessionAssertionsForInvalidContexts()

            guard acceptedGeneration == execution.generation else {
                return latestEntitlement()
                    ?? finalOutput.snapshot
            }

            latestObservations = finalOutput.observations
            return finalOutput.snapshot
        }
    }

    func acceptedOutput(
        _ output: EntitlementRefreshOutput
    ) -> EntitlementRefreshOutput {
        let observations = acceptedObservations(output.observations)
        let acceptedSources = Set(observations.compactMap { observation in
            observation.assertion == nil ? nil : observation.source
        })
        let assertions = output.refreshedAssertions.filter { source, _ in
            acceptedSources.contains(source) && sourceContextIsCurrent(source)
        }
        return EntitlementRefreshOutput(
            snapshot: aggregator.resolve(
                observations: observations,
                now: clock.now()
            ),
            observations: observations,
            refreshedAssertions: assertions
        )
    }

    func acceptedObservations(
        _ observations: [EntitlementSourceObservation]
    ) -> [EntitlementSourceObservation] {
        observations.map { observation in
            guard sourceContextIsCurrent(observation.source) else {
                return EntitlementSourceObservation(
                    source: observation.source,
                    freshnessPolicy: observation.freshnessPolicy,
                    assertion: nil,
                    isFromCurrentRefresh: false
                )
            }
            return observation
        }
    }

    func sourceContextIsCurrent(_ source: EntitlementSource) -> Bool {
        registrations.first(where: { $0.source == source })?
            .acceptanceGate.acceptsCurrentContext() == true
    }

    func discardSessionAssertionsForInvalidContexts() {
        for registration in registrations
            where !registration.acceptanceGate.acceptsCurrentContext() {
            sessionAssertions[registration.source] = nil
        }
    }
}
