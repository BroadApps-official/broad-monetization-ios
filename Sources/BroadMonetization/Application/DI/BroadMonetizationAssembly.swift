import BroadCore
import Swinject

public final class BroadMonetizationAssembly: Assembly {
    private let entitlementStatusProvider: any EntitlementStatusProviderProtocol
    private let entitlementRepository: (any EntitlementRepositoryProtocol)?
    private let refreshEntitlementUseCase: (any RefreshEntitlementUseCaseProtocol)?
    private let services: BroadMonetizationServices?

    public init(
        entitlementStatusProvider: any EntitlementStatusProviderProtocol = UnknownEntitlementStatusProvider(),
        services: BroadMonetizationServices? = nil
    ) {
        self.entitlementStatusProvider = entitlementStatusProvider
        entitlementRepository = nil
        refreshEntitlementUseCase = nil
        self.services = services
    }

    public convenience init(
        entitlementEngine: EntitlementEngine,
        services: BroadMonetizationServices? = nil
    ) {
        self.init(
            entitlementStatusProvider: entitlementEngine,
            entitlementRepository: entitlementEngine,
            refreshEntitlementUseCase: entitlementEngine,
            services: services
        )
    }

    private init(
        entitlementStatusProvider: any EntitlementStatusProviderProtocol,
        entitlementRepository: any EntitlementRepositoryProtocol,
        refreshEntitlementUseCase: any RefreshEntitlementUseCaseProtocol,
        services: BroadMonetizationServices?
    ) {
        self.entitlementStatusProvider = entitlementStatusProvider
        self.entitlementRepository = entitlementRepository
        self.refreshEntitlementUseCase = refreshEntitlementUseCase
        self.services = services
    }

    public func assemble(container: Container) {
        container
            .register(BroadMonetizationModule.self) { resolver in
                guard let coreModule = resolver.resolve(BroadCoreModule.self) else {
                    preconditionFailure("BroadCoreAssembly must be registered before BroadMonetizationAssembly")
                }

                return BroadMonetizationModule(
                    coreIdentifier: coreModule.identifier,
                    isAdaptyLinked: BroadAdaptySDKAvailability.isLinked
                )
            }
            .inObjectScope(.container)

        container
            .register(EntitlementStatusProviderProtocol.self) { [entitlementStatusProvider] _ in
                entitlementStatusProvider
            }
            .inObjectScope(.container)

        if let entitlementRepository {
            container
                .register(EntitlementRepositoryProtocol.self) { _ in
                    entitlementRepository
                }
                .inObjectScope(.container)
        }

        if let refreshEntitlementUseCase {
            container
                .register(RefreshEntitlementUseCaseProtocol.self) { _ in
                    refreshEntitlementUseCase
                }
                .inObjectScope(.container)
        }

        registerServices(in: container)
    }
}

private extension BroadMonetizationAssembly {
    func registerServices(in container: Container) {
        guard let services else {
            return
        }

        container.register(ActivateMonetizationUseCaseProtocol.self) { _ in services.activate }
            .inObjectScope(.container)
        container.register(LoadPaywallUseCaseProtocol.self) { _ in services.loadPaywall }
            .inObjectScope(.container)
        container.register(SelectProductUseCaseProtocol.self) { _ in services.selectProduct }
            .inObjectScope(.container)
        container.register(PurchaseSelectedProductUseCaseProtocol.self) { _ in services.purchaseProduct }
            .inObjectScope(.container)
        container.register(CheckoutSelectedProductUseCaseProtocol.self) { _ in services.checkoutProduct }
            .inObjectScope(.container)
        container.register(RestorePurchasesUseCaseProtocol.self) { _ in services.restorePurchases }
            .inObjectScope(.container)
        container.register(MonetizationAnalyticsProtocol.self) { _ in services.analytics }
            .inObjectScope(.container)
        container.register(PaywallPresentationLifecycleProtocol.self) { _ in
            services.paywallPresentationLifecycle
        }
        .inObjectScope(.container)
        container.register(TrackPaywallEventUseCaseProtocol.self) { _ in
            services.trackPaywallEvent
        }
        .inObjectScope(.container)
        container.register(MonetizationOperationGate.self) { _ in services.operationGate }
            .inObjectScope(.container)
    }
}
