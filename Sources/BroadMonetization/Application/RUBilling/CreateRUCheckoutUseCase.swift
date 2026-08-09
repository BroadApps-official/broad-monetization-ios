struct CreateRUCheckoutUseCase: CreateRUCheckoutUseCaseProtocol {
    private let repository: any RUCheckoutRepositoryProtocol

    init(repository: any RUCheckoutRepositoryProtocol) {
        self.repository = repository
    }

    func callAsFunction(
        _ request: RUCheckoutRequest
    ) async -> RUCheckoutCreationOutcome {
        await repository.createCheckout(request)
    }
}
