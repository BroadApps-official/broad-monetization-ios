public struct FallbackRUSubscriptionRepository: RUSubscriptionRepositoryProtocol {
    private let primary: any RUSubscriptionRepositoryProtocol
    private let legacy: (any RUSubscriptionRepositoryProtocol)?
    private let allowsLegacyFallback: Bool

    public init(
        primary: any RUSubscriptionRepositoryProtocol,
        legacy: (any RUSubscriptionRepositoryProtocol)?,
        allowsLegacyFallback: Bool
    ) {
        precondition(
            !allowsLegacyFallback || legacy != nil,
            "Enabled RU cancellation fallback requires an explicit legacy repository"
        )
        self.primary = primary
        self.legacy = legacy
        self.allowsLegacyFallback = allowsLegacyFallback
    }

    public func cancelSubscription(
        id: RUSubscriptionID
    ) async -> RUSubscriptionCancellationOutcome {
        let primaryOutcome = await primary.cancelSubscription(id: id)
        guard allowsLegacyFallback,
              let legacy,
              primaryOutcome.requiresFallback
        else {
            return primaryOutcome
        }
        return await legacy.cancelSubscription(id: id)
    }
}

private extension RUSubscriptionCancellationOutcome {
    var requiresFallback: Bool {
        switch self {
        case .unavailable, .failed:
            true
        case .cancelled, .alreadyInactive:
            false
        }
    }
}
