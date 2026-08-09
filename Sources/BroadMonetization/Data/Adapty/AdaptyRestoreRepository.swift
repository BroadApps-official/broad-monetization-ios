import Adapty
import BroadCore

public actor AdaptyRestoreRepository: RestoreRepositoryProtocol {
    private let configuration: AdaptyPlatformConfiguration
    private let identityProvider: any AdaptyIdentityProviderProtocol
    private let context: AdaptyRepositoryContext
    private let messages: AdaptyMonetizationMessages

    private var isRestoring = false

    public init(
        configuration: AdaptyPlatformConfiguration,
        identityProvider: any AdaptyIdentityProviderProtocol,
        context: AdaptyRepositoryContext,
        messages: AdaptyMonetizationMessages
    ) {
        self.configuration = configuration
        self.identityProvider = identityProvider
        self.context = context
        self.messages = messages
    }

    public func restorePurchases() async -> RestoreAttemptOutcome {
        guard !isRestoring else {
            return .failed(unavailableError(code: "monetization.adapty.restore-in-progress"))
        }

        isRestoring = true
        defer { isRestoring = false }

        guard let outcome = await AdaptySDKActivationGate.shared.perform(
            configuration: configuration,
            identityProvider: identityProvider,
            compositionID: context.sdkCompositionID,
            operation: { [self] in
                await restoreUnderLease()
            }
        ) else {
            return .failed(unavailableError(code: "monetization.adapty.restore-activation-unavailable"))
        }
        return outcome
    }
}

private extension AdaptyRestoreRepository {
    func restoreUnderLease() async -> RestoreAttemptOutcome {
        do {
            _ = try await Adapty.restorePurchases()
            return Task.isCancelled
                ? .failed(unavailableError(code: "monetization.adapty.restore-cancelled"))
                : .completed
        } catch {
            return .failed(unavailableError(code: "monetization.adapty.restore-failed"))
        }
    }

    func unavailableError(code: String) -> AppError {
        AppError(
            kind: .unavailable,
            userMessage: messages.restoreFailed,
            diagnosticCode: code,
            isRetryable: true
        )
    }
}
