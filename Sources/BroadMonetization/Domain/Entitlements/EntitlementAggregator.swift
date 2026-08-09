import Foundation

public struct EntitlementAggregator: Sendable {
    public init() {}

    public func resolve(
        observations: [EntitlementSourceObservation],
        now: Date
    ) -> EntitlementSnapshot {
        precondition(
            Set(observations.map(\.source)).count == observations.count,
            "Entitlement observations must have unique sources"
        )

        let evaluations = observations
            .map { evaluate($0, now: now) }
            .sorted { sourceIndex($0.source) < sourceIndex($1.source) }

        if evaluations.contains(where: { $0.state == .active }) {
            return activeSnapshot(evaluations: evaluations, now: now)
        }

        if !evaluations.isEmpty, evaluations.allSatisfy({ $0.state == .inactive }) {
            return inactiveSnapshot(evaluations: evaluations, now: now)
        }

        return unresolvedSnapshot(evaluations: evaluations, now: now)
    }
}

extension EntitlementAggregator {
    private func evaluate(
        _ observation: EntitlementSourceObservation,
        now: Date
    ) -> EntitlementSourceEvaluation {
        guard
            now.timeIntervalSinceReferenceDate.isFinite,
            let assertion = observation.assertion,
            assertion.hasValidStructure,
            now >= assertion.validatedAt
        else {
            return unresolvedEvaluation(for: observation.source, assertion: observation.assertion)
        }

        if observation.isFromCurrentRefresh {
            guard
                let freshDeadline = cappedFreshDeadline(
                    assertion,
                    policy: observation.freshnessPolicy
                ),
                now < freshDeadline
            else {
                return cachedEvaluation(
                    assertion,
                    policy: observation.freshnessPolicy,
                    now: now
                )
            }

            return refreshedEvaluation(assertion, now: now)
        }

        return cachedEvaluation(
            assertion,
            policy: observation.freshnessPolicy,
            now: now
        )
    }

    private func refreshedEvaluation(
        _ assertion: EntitlementSourceAssertion,
        now: Date
    ) -> EntitlementSourceEvaluation {
        switch assertion.state {
        case let .active(validity):
            guard validity.isActive(at: now) else {
                return unresolvedEvaluation(
                    for: assertion.source,
                    assertion: assertion
                )
            }

            return EntitlementSourceEvaluation(
                source: assertion.source,
                state: .active,
                freshness: .refreshed,
                activeValidity: validity,
                validatedAt: assertion.validatedAt
            )
        case .inactive:
            return EntitlementSourceEvaluation(
                source: assertion.source,
                state: .inactive,
                freshness: .refreshed,
                activeValidity: nil,
                validatedAt: assertion.validatedAt
            )
        }
    }

    private func cachedEvaluation(
        _ assertion: EntitlementSourceAssertion,
        policy: EntitlementFreshnessPolicy,
        now: Date
    ) -> EntitlementSourceEvaluation {
        guard let freshDeadline = cappedFreshDeadline(assertion, policy: policy) else {
            return unresolvedEvaluation(for: assertion.source, assertion: assertion)
        }

        switch assertion.state {
        case let .active(validity):
            guard validity.isActive(at: now) else {
                return unresolvedEvaluation(for: assertion.source, assertion: assertion)
            }

            if now < freshDeadline {
                return activeEvaluation(assertion, validity: validity, freshness: .cached)
            }

            guard
                let graceDeadline = cappedGraceDeadline(assertion, policy: policy),
                now < graceDeadline
            else {
                return unresolvedEvaluation(for: assertion.source, assertion: assertion)
            }

            return activeEvaluation(assertion, validity: validity, freshness: .grace)
        case .inactive:
            guard now < freshDeadline else {
                return unresolvedEvaluation(for: assertion.source, assertion: assertion)
            }

            return EntitlementSourceEvaluation(
                source: assertion.source,
                state: .inactive,
                freshness: .cached,
                activeValidity: nil,
                validatedAt: assertion.validatedAt
            )
        }
    }

    private func activeEvaluation(
        _ assertion: EntitlementSourceAssertion,
        validity: EntitlementActiveValidity,
        freshness: EntitlementFreshness
    ) -> EntitlementSourceEvaluation {
        EntitlementSourceEvaluation(
            source: assertion.source,
            state: .active,
            freshness: freshness,
            activeValidity: validity,
            validatedAt: assertion.validatedAt
        )
    }

    private func unresolvedEvaluation(
        for source: EntitlementSource,
        assertion: EntitlementSourceAssertion?
    ) -> EntitlementSourceEvaluation {
        EntitlementSourceEvaluation(
            source: source,
            state: .unresolved,
            freshness: .unresolved,
            activeValidity: nil,
            validatedAt: assertion?.validatedAt
        )
    }

    private func activeSnapshot(
        evaluations: [EntitlementSourceEvaluation],
        now: Date
    ) -> EntitlementSnapshot {
        let active = evaluations.filter { $0.state == .active }
        let freshness: EntitlementFreshness = if active.contains(where: { $0.freshness == .refreshed }) {
            .refreshed
        } else if active.contains(where: { $0.freshness == .cached }) {
            .cached
        } else {
            .grace
        }

        return EntitlementSnapshot(
            state: .active,
            sources: evaluations,
            activeValidity: aggregateValidity(active),
            freshness: freshness,
            validatedAt: active.compactMap(\.validatedAt).max(),
            evaluatedAt: now
        )
    }

    private func inactiveSnapshot(
        evaluations: [EntitlementSourceEvaluation],
        now: Date
    ) -> EntitlementSnapshot {
        let isFullyRefreshed = evaluations.allSatisfy {
            $0.freshness == .refreshed
        }

        return EntitlementSnapshot(
            state: .inactive,
            sources: evaluations,
            activeValidity: nil,
            freshness: isFullyRefreshed ? .refreshed : .cached,
            validatedAt: evaluations.compactMap(\.validatedAt).min(),
            evaluatedAt: now
        )
    }

    private func unresolvedSnapshot(
        evaluations: [EntitlementSourceEvaluation],
        now: Date
    ) -> EntitlementSnapshot {
        EntitlementSnapshot(
            state: .unresolved,
            sources: evaluations,
            activeValidity: nil,
            freshness: .unresolved,
            validatedAt: evaluations.compactMap(\.validatedAt).max(),
            evaluatedAt: now
        )
    }

    private func aggregateValidity(
        _ active: [EntitlementSourceEvaluation]
    ) -> EntitlementActiveValidity {
        if active.contains(where: \.isLifetime) {
            return .lifetime
        }

        let validities = active.compactMap(\.activeValidity)
        if validities.contains(.unspecified) {
            return .unspecified
        }

        let expiration = active.compactMap(\.expirationDate).max()
        return expiration.map { .expires(at: $0) } ?? .unspecified
    }

    private func cappedFreshDeadline(
        _ assertion: EntitlementSourceAssertion,
        policy: EntitlementFreshnessPolicy
    ) -> Date? {
        guard let policyDeadline = adding(
            policy.timeToLive,
            to: assertion.validatedAt
        ) else {
            return nil
        }

        return min(assertion.freshUntil, policyDeadline)
    }

    private func cappedGraceDeadline(
        _ assertion: EntitlementSourceAssertion,
        policy: EntitlementFreshnessPolicy
    ) -> Date? {
        let totalDuration = policy.timeToLive + policy.offlineActiveGrace
        guard totalDuration.isFinite else {
            return nil
        }

        guard let policyDeadline = adding(totalDuration, to: assertion.validatedAt) else {
            return nil
        }

        let storedDeadline = min(assertion.activeGraceUntil, policyDeadline)
        guard case let .active(validity) = assertion.state else {
            return storedDeadline
        }

        guard case let .expires(expirationDate) = validity else {
            return storedDeadline
        }

        return min(storedDeadline, expirationDate)
    }

    private func adding(
        _ interval: TimeInterval,
        to date: Date
    ) -> Date? {
        let timestamp = date.timeIntervalSinceReferenceDate + interval
        guard timestamp.isFinite else {
            return nil
        }

        return Date(timeIntervalSinceReferenceDate: timestamp)
    }

    private func sourceIndex(_ source: EntitlementSource) -> Int {
        EntitlementSource.allCases.firstIndex(of: source) ?? .max
    }
}
