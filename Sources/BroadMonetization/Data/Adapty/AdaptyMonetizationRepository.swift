import BroadCore

public struct AdaptyMonetizationRepository: MonetizationRepositoryProtocol {
    private let configuration: AdaptyPlatformConfiguration
    private let identityProvider: any AdaptyIdentityProviderProtocol
    private let context: AdaptyRepositoryContext
    private let messages: AdaptyMonetizationMessages

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

    public func activate() async -> MonetizationActivationOutcome {
        let activated = await AdaptySDKActivationGate.shared.perform(
            configuration: configuration,
            identityProvider: identityProvider,
            compositionID: context.sdkCompositionID,
            operation: { !Task.isCancelled }
        ) ?? false
        guard activated else {
            return .unavailable(
                AppError(
                    kind: .unavailable,
                    userMessage: messages.activationUnavailable,
                    diagnosticCode: "monetization.adapty.activation-unavailable",
                    isRetryable: true
                )
            )
        }
        return .activated
    }
}
