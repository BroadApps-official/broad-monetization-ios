/// A failed network request must return unavailable, never a persisted catalog.
public protocol FreshRUCatalogRepositoryProtocol: RUCatalogRepositoryProtocol {
    func loadFreshCatalog() async -> RUCatalogLoadOutcome
}
