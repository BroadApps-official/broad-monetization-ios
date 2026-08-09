public struct ActivateMonetizationUseCase: ActivateMonetizationUseCaseProtocol {
    private let repository: any MonetizationRepositoryProtocol

    public init(repository: any MonetizationRepositoryProtocol) {
        self.repository = repository
    }

    public func callAsFunction() async -> MonetizationActivationOutcome {
        await repository.activate()
    }
}
