/// One instance belongs to one authenticated RU composition. It reports only
/// actual appearances, never catalog loads, selections or successful payments.
public actor RUBillingExperimentTracker {
    private let repository: any RUExperimentRepositoryProtocol
    private let gate: RUBillingGate
    private let storefrontRepository: any StorefrontRepositoryProtocol
    private let authorizationBinding: SubjectAuthorizationBinding
    private let onOutcome: @Sendable (RUExperimentTrackingOutcome) -> Void
    private var reports: [PaywallPresentationID: Task<RUExperimentTrackingOutcome, Never>] = [:]
    private var ended: Set<PaywallPresentationID> = []
    private var endedOrder: [PaywallPresentationID] = []

    public init(
        repository: any RUExperimentRepositoryProtocol,
        gate: RUBillingGate,
        storefrontRepository: any StorefrontRepositoryProtocol,
        authorizationBinding: SubjectAuthorizationBinding,
        onOutcome: @escaping @Sendable (RUExperimentTrackingOutcome) -> Void = { _ in }
    ) {
        self.repository = repository
        self.gate = gate
        self.storefrontRepository = storefrontRepository
        self.authorizationBinding = authorizationBinding
        self.onOutcome = onOutcome
    }

    /// A new appearance must use a fresh payload.presentationID. Parallel calls
    /// for one presentation join the same attempt, including an unsuccessful one.
    public func trackShown(
        _ paywall: PaywallPayload,
        placement: String
    ) async -> RUExperimentTrackingOutcome {
        await beginTracking(PaywallAnalyticsContext(paywall: paywall), placement: placement).value
    }

    /// Releases completed presentation state. In-flight requests keep their
    /// captured subject binding and may finish without blocking dismissal.
    public func presentationDidEnd(_ presentationID: PaywallPresentationID) {
        guard ended.insert(presentationID).inserted else {
            return
        }
        endedOrder.append(presentationID)
        // Active presentations are never evicted. Only terminal tombstones
        // have bounded retention, like the SDK raw-product registry.
        while endedOrder.count > 128 {
            let oldest = endedOrder.removeFirst()
            ended.remove(oldest)
            reports.removeValue(forKey: oldest)
        }
    }

    func beginTracking(
        _ context: PaywallAnalyticsContext,
        placement: String
    ) -> Task<RUExperimentTrackingOutcome, Never> {
        if let report = reports[context.presentationID] {
            return report
        }
        guard !ended.contains(context.presentationID) else {
            return Task { .presentationEnded }
        }
        let repository = repository
        let gate = gate
        let storefront = storefrontRepository
        let binding = authorizationBinding
        let onOutcome = onOutcome
        let report = Task {
            let outcome = await RUExperimentReportOperation(
                repository: repository, gate: gate,
                storefrontRepository: storefront, authorizationBinding: binding
            ).run(context: context, placement: placement)
            onOutcome(outcome)
            return outcome
        }
        reports[context.presentationID] = report
        return report
    }
}

private struct RUExperimentReportOperation: Sendable {
    let repository: any RUExperimentRepositoryProtocol
    let gate: RUBillingGate
    let storefrontRepository: any StorefrontRepositoryProtocol
    let authorizationBinding: SubjectAuthorizationBinding

    func run(context: PaywallAnalyticsContext, placement: String) async -> RUExperimentTrackingOutcome {
        let remote = context.remoteConfiguration
        let storefront: Storefront? = switch await storefrontRepository.currentStorefront() {
        case let .available(value): value
        case .unavailable: nil
        }
        guard gate.allows(remoteConfiguration: remote, storefront: storefront) else {
            return .useAdapty
        }
        guard let metadata = remote.ruExperiment else {
            return .outsideExperiment
        }
        guard let event = RUExperimentEvent(metadata: metadata, placement: placement) else {
            return .invalidPlacement
        }
        guard authorizationBinding.isCurrent(), !Task.isCancelled else {
            return .authorizationUnavailable
        }
        return await report(event)
    }

    private func report(_ event: RUExperimentEvent) async -> RUExperimentTrackingOutcome {
        guard case let .assigned(assignment) = await repository.assign(event),
              assignment.metadata.experimentCode == event.experimentCode,
              assignment.requestedSegmentMatches == (assignment.metadata.segmentCode == event.segmentCode)
        else {
            return .assignmentFailed
        }
        guard authorizationBinding.isCurrent(), !Task.isCancelled else {
            return .authorizationUnavailable
        }
        guard let shown = RUExperimentEvent(metadata: assignment.metadata, placement: event.placement),
              await repository.paywallShown(shown) == .logged
        else {
            return .impressionFailed
        }
        guard authorizationBinding.isCurrent(), !Task.isCancelled else {
            return .authorizationUnavailable
        }
        return .reported(requestedSegmentMatches: assignment.requestedSegmentMatches)
    }
}
