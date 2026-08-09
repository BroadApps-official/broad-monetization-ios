import Swinject

public final class RUBillingAssembly: Assembly {
    private let services: RUBillingServices

    public init(services: RUBillingServices) {
        self.services = services
    }

    public func assemble(container: Container) {
        container.register(RUBillingServices.self) { [services] _ in services }
            .inObjectScope(.container)
        registerCatalog(in: container)
        registerCheckout(in: container)
    }
}

private extension RUBillingAssembly {
    func registerCatalog(in container: Container) {
        let catalog = services.catalog
        container.register(RUCatalogRepositoryProtocol.self) { _ in catalog.repository }
            .inObjectScope(.container)
        container.register(ResolveRUCatalogProductUseCase.self) { _ in catalog.resolveProduct }
            .inObjectScope(.container)
        container.register(ResolveCheckoutMethodsUseCaseProtocol.self) { _ in catalog.resolveCheckoutMethods }
            .inObjectScope(.container)
    }

    func registerCheckout(in container: Container) {
        let checkout = services.checkout
        container.register(StartSelectedRUCheckoutUseCaseProtocol.self) { _ in
            checkout.startSelectedProduct
        }
        .inObjectScope(.container)
        container.register(CheckoutSelectedProductUseCaseProtocol.self) { resolver in
            guard let applePurchase = resolver.resolve(
                PurchaseSelectedProductUseCaseProtocol.self
            ) else {
                preconditionFailure(
                    "BroadMonetizationAssembly must be registered before RUBillingAssembly"
                )
            }
            guard let sharedOperationGate = resolver.resolve(
                MonetizationOperationGate.self
            ) else {
                preconditionFailure(
                    "BroadMonetizationAssembly must register the shared operation gate"
                )
            }
            precondition(
                sharedOperationGate === checkout.operationGate,
                "RU billing must use BroadMonetizationServices.operationGate"
            )
            return CheckoutSelectedProductUseCase(
                applePurchase: applePurchase,
                ruCheckout: checkout.startSelectedProduct
            )
        }
        .inObjectScope(.container)
        container.register(RUPaymentReturnCoordinator.self) { _ in checkout.applicationReturn }
            .inObjectScope(.container)
        container.register(CancelRUSubscriptionUseCaseProtocol.self) { _ in checkout.cancelSubscription }
            .inObjectScope(.container)
    }
}
