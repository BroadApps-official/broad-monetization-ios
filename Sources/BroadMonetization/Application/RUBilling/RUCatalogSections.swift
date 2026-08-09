public struct RUCatalogSections: Equatable, Sendable {
    public let subscriptions: [RUCatalogProduct]
    public let tokens: [RUCatalogProduct]
    public let coupons: [RUCatalogProduct]
    public let unknown: [RUCatalogProduct]

    public init(catalog: RUCatalogPayload) {
        subscriptions = catalog.products.filter { $0.kind == .subscription }
        tokens = catalog.products.filter { $0.kind == .tokens }
        coupons = catalog.products.filter { $0.kind == .coupon }
        unknown = catalog.products.filter { $0.kind == .unknown }
    }
}

public struct ResolveRUCatalogProductUseCase: Sendable {
    private let catalogRepository: any RUCatalogRepositoryProtocol
    private let matcher: RUCatalogProductMatcher

    public init(
        catalogRepository: any RUCatalogRepositoryProtocol,
        matcher: RUCatalogProductMatcher = RUCatalogProductMatcher()
    ) {
        self.catalogRepository = catalogRepository
        self.matcher = matcher
    }

    public func callAsFunction(
        product: MonetizationProduct,
        kind: RUCatalogProductKind
    ) async -> RUCatalogProduct? {
        guard case let .loaded(catalog) = await catalogRepository.loadCatalog() else {
            return nil
        }
        return matcher.match(product: product, kind: kind, in: catalog)
    }
}
