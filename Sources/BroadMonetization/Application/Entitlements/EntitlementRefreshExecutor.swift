import BroadCore
import Foundation

struct EntitlementRefreshOutput: Sendable {
    let snapshot: EntitlementSnapshot
    let observations: [EntitlementSourceObservation]
    let refreshedAssertions: [EntitlementSource: EntitlementSourceAssertion]
}

enum EntitlementRefreshExecutor {
    static func perform(
        registrations: [EntitlementSourceRuntime],
        timeoutPolicy: TimeoutPolicy,
        clock: CacheClock,
        aggregator: EntitlementAggregator,
        cacheReaders: [EntitlementSource: EntitlementCacheReader],
        sessionAssertions: [EntitlementSource: EntitlementSourceAssertion],
        refreshPolicy: EntitlementRefreshPolicy,
        refreshGeneration: UInt64
    ) async -> EntitlementRefreshOutput {
        let continuousClock = ContinuousClock()
        let deadline = continuousClock.now.advanced(by: timeoutPolicy.limit)
        let outputs = await withTaskGroup(
            of: SourceRefreshOutput.self,
            returning: [SourceRefreshOutput].self
        ) { group in
            for registration in registrations {
                guard let cacheReader = cacheReaders[registration.source] else {
                    preconditionFailure("Missing entitlement cache reader")
                }

                group.addTask {
                    await refresh(
                        registration: registration,
                        cacheReader: cacheReader,
                        deadline: deadline,
                        clock: clock,
                        sessionAssertion: sessionAssertions[registration.source],
                        refreshGeneration: refreshGeneration,
                        forceNewGeneration: refreshPolicy == .startNewGeneration
                    )
                }
            }

            var values: [SourceRefreshOutput] = []
            values.reserveCapacity(registrations.count)
            for await value in group {
                values.append(value)
            }
            return values
        }

        let observations = outputs.map(\.observation)
        let refreshedAssertions = outputs.reduce(
            into: [EntitlementSource: EntitlementSourceAssertion]()
        ) { result, output in
            guard let assertion = output.refreshedAssertion else {
                return
            }
            result[assertion.source] = assertion
        }

        return EntitlementRefreshOutput(
            snapshot: aggregator.resolve(
                observations: observations,
                now: clock.now()
            ),
            observations: observations,
            refreshedAssertions: refreshedAssertions
        )
    }
}

private extension EntitlementRefreshExecutor {
    struct SourceRefreshOutput: Sendable {
        let observation: EntitlementSourceObservation
        let refreshedAssertion: EntitlementSourceAssertion?
    }

    struct SourceAttempt: Sendable {
        let resolution: EntitlementSourceResolution
        let validatedAt: Date
    }

    static func refresh(
        registration: EntitlementSourceRuntime,
        cacheReader: EntitlementCacheReader,
        deadline: ContinuousClock.Instant,
        clock: CacheClock,
        sessionAssertion: EntitlementSourceAssertion?,
        refreshGeneration: UInt64,
        forceNewGeneration: Bool
    ) async -> SourceRefreshOutput {
        async let cachedAssertion = cacheReader.read(before: deadline)
        async let sourceAttempt = resolveSource(
            registration: registration,
            deadline: deadline,
            clock: clock,
            refreshGeneration: refreshGeneration,
            forceNewGeneration: forceNewGeneration
        )
        let (cachedAssertionValue, sourceAttemptValue) = await (
            cachedAssertion,
            sourceAttempt
        )
        guard registration.acceptanceGate.acceptsCurrentContext() else {
            return output(registration: registration, assertion: nil)
        }
        let fallbackAssertion = sessionAssertion ?? cachedAssertionValue

        guard let assertion = makeAssertion(
            from: sourceAttemptValue.resolution,
            registration: registration,
            validatedAt: sourceAttemptValue.validatedAt
        ) else {
            return output(
                registration: registration,
                assertion: fallbackAssertion
            )
        }

        return SourceRefreshOutput(
            observation: EntitlementSourceObservation(
                source: registration.source,
                freshnessPolicy: registration.freshnessPolicy,
                assertion: assertion,
                isFromCurrentRefresh: true
            ),
            refreshedAssertion: assertion
        )
    }

    static func output(
        registration: EntitlementSourceRuntime,
        assertion: EntitlementSourceAssertion?
    ) -> SourceRefreshOutput {
        SourceRefreshOutput(
            observation: EntitlementSourceObservation(
                source: registration.source,
                freshnessPolicy: registration.freshnessPolicy,
                assertion: assertion,
                isFromCurrentRefresh: false
            ),
            refreshedAssertion: nil
        )
    }

    static func resolveSource(
        registration: EntitlementSourceRuntime,
        deadline: ContinuousClock.Instant,
        clock: CacheClock,
        refreshGeneration: UInt64,
        forceNewGeneration: Bool
    ) async -> SourceAttempt {
        let resolution = await EntitlementSourceResolver(
            runtime: registration,
            refreshGeneration: refreshGeneration,
            forceNewGeneration: forceNewGeneration
        ).resolve(before: deadline)
        return SourceAttempt(
            resolution: resolution,
            validatedAt: clock.now()
        )
    }

    static func makeAssertion(
        from resolution: EntitlementSourceResolution,
        registration: EntitlementSourceRuntime,
        validatedAt: Date
    ) -> EntitlementSourceAssertion? {
        guard
            validatedAt.timeIntervalSinceReferenceDate.isFinite,
            let freshUntil = adding(
                registration.freshnessPolicy.timeToLive,
                to: validatedAt
            )
        else {
            return nil
        }

        let state: ResolvedEntitlementState
        let activeGraceUntil: Date

        switch resolution {
        case let .active(validity):
            guard validity.isActive(at: validatedAt) else {
                return nil
            }
            guard let graceUntil = adding(
                registration.freshnessPolicy.offlineActiveGrace,
                to: freshUntil
            ) else {
                return nil
            }
            state = .active(validity)
            activeGraceUntil = graceUntil
        case .inactive:
            state = .inactive
            activeGraceUntil = freshUntil
        case .unresolved:
            return nil
        }

        return EntitlementSourceAssertion(
            source: registration.source,
            state: state,
            validatedAt: validatedAt,
            freshUntil: freshUntil,
            activeGraceUntil: activeGraceUntil
        )
    }

    static func adding(
        _ interval: TimeInterval,
        to date: Date
    ) -> Date? {
        let timestamp = date.timeIntervalSinceReferenceDate + interval
        guard timestamp.isFinite else {
            return nil
        }

        return Date(timeIntervalSinceReferenceDate: timestamp)
    }
}
