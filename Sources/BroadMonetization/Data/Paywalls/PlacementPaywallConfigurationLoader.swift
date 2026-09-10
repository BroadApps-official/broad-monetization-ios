/// Configuration follows the selected placement; main supplies missing keys.
/// Products, variation and SDK handles always belong to the returned paywall.
struct PlacementConfiguredPaywall<ProviderPaywall: Sendable>: Sendable {
    let paywall: ProviderPaywall?
    let remoteConfiguration: RemotePaywallConfiguration?
}

/// One loader belongs to one SDK identity/composition. Only concurrent main
/// requests are shared; completed responses are never reused as fresh gates.
actor PlacementPaywallConfigurationLoader<ProviderPaywall: Sendable> {
    typealias Fetch = @Sendable (PlacementID) async -> ProviderPaywall?
    typealias Parse = @Sendable (ProviderPaywall, ProviderPaywall?) -> RemotePaywallConfiguration

    private let store: LastValidRemoteConfigurationStore
    private var sequence: UInt64 = 0
    private var inFlight: (token: UInt64, task: Task<ProviderPaywall?, Never>)?

    init(store: LastValidRemoteConfigurationStore) {
        self.store = store
    }

    func load(
        for placementID: PlacementID,
        fetch: @escaping Fetch,
        parse: @escaping Parse
    ) async -> PlacementConfiguredPaywall<ProviderPaywall> {
        guard !Task.isCancelled else {
            return PlacementConfiguredPaywall(paywall: nil, remoteConfiguration: nil)
        }
        let paywall = if placementID == .main {
            await loadMain(fetch: fetch)
        } else {
            await fetch(placementID)
        }
        guard !Task.isCancelled else {
            return PlacementConfiguredPaywall(paywall: nil, remoteConfiguration: nil)
        }
        let main = placementID == .main ? nil : await loadMain(fetch: fetch)
        guard !Task.isCancelled else {
            return PlacementConfiguredPaywall(paywall: nil, remoteConfiguration: nil)
        }
        let parsed = if let paywall {
            parse(paywall, main)
        } else {
            main.map { parse($0, nil) }
        }
        let resolved: RemotePaywallConfiguration? = if let parsed {
            await store.resolve(parsed, for: placementID)
        } else {
            nil
        }
        return PlacementConfiguredPaywall(paywall: paywall, remoteConfiguration: resolved)
    }

    private func loadMain(fetch: @escaping Fetch) async -> ProviderPaywall? {
        if let inFlight {
            return await inFlight.task.value
        }
        sequence &+= 1
        let token = sequence
        let task = Task {
            await fetch(.main)
        }
        inFlight = (token, task)
        let result = await task.value
        if inFlight?.token == token {
            inFlight = nil
        }
        return result
    }
}
