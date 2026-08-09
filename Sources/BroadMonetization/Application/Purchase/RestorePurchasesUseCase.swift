import BroadCore

public actor RestorePurchasesUseCase: RestorePurchasesUseCaseProtocol {
    private let repository: any RestoreRepositoryProtocol
    private let entitlementRepository: any EntitlementRepositoryProtocol
    private let analytics: any MonetizationAnalyticsProtocol
    public nonisolated let monetizationOperationGate: MonetizationOperationGate
    private let verificationUnavailableError: AppError

    public init(
        repository: any RestoreRepositoryProtocol,
        entitlementRepository: any EntitlementRepositoryProtocol,
        analytics: any MonetizationAnalyticsProtocol,
        operationGate: MonetizationOperationGate,
        verificationUnavailableError: AppError
    ) {
        self.repository = repository
        self.entitlementRepository = entitlementRepository
        self.analytics = NonBlockingMonetizationAnalytics.wrapping(analytics)
        monetizationOperationGate = operationGate
        self.verificationUnavailableError = verificationUnavailableError
    }

    public func callAsFunction() async -> RestoreOutcome {
        guard let lease = await monetizationOperationGate.acquire(.restore) else {
            return .unavailable(verificationUnavailableError)
        }

        let outcome = await performRestore()
        await monetizationOperationGate.release(lease)
        return outcome
    }
}

extension RestorePurchasesUseCase: MonetizationOperationGateProviding {}

private extension RestorePurchasesUseCase {
    func performRestore() async -> RestoreOutcome {
        let context = RestoreAnalyticsContext(attemptID: .generated())
        await analytics.track(.restoreStarted(context))

        let providerOutcome = await repository.restorePurchases()
        let snapshot = await entitlementRepository.refreshEntitlement(
            policy: .startNewGeneration
        )
        if snapshot.isCurrentActiveConfirmed {
            await analytics.track(.restoreSuccess(context))
            return .restored(snapshot)
        }

        switch providerOutcome {
        case let .failed(error):
            await analytics.track(
                .restoreUnavailable(
                    context,
                    failure: MonetizationAnalyticsFailure(error: error)
                )
            )
            return .failed(error)
        case .completed:
            if snapshot.isCurrentInactiveConfirmed {
                await analytics.track(.restoreNothingFound(context))
                return .nothingFound
            }

            await analytics.track(
                .restoreUnavailable(
                    context,
                    failure: MonetizationAnalyticsFailure(
                        error: verificationUnavailableError
                    )
                )
            )
            return .unavailable(verificationUnavailableError)
        }
    }
}
