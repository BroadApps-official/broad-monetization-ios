/// Keeps the common main configuration separate from the paywall whose
/// products, variation and SDK handles will actually be presented.
struct MainConfiguredPaywall<ProviderPaywall: Sendable>: Sendable {
    let paywall: ProviderPaywall?
    let remoteConfiguration: RemotePaywallConfiguration?
}

/// One loader belongs to one SDK identity/composition. Only concurrent main
/// requests are shared; completed responses are never reused as fresh gates.
actor MainPaywallConfigurationLoader<ProviderPaywall: Sendable> {
    typealias Fetch = @Sendable (PlacementID) async -> ProviderPaywall?
    typealias Parse = @Sendable (ProviderPaywall) -> RemotePaywallConfiguration

    private let store: LastValidRemoteConfigurationStore
    private var sequence: UInt64 = 0
    private var inFlight: (token: UInt64, task: Task<MainConfiguredPaywall<ProviderPaywall>, Never>)?

    init(store: LastValidRemoteConfigurationStore) {
        self.store = store
    }

    func load(
        for placementID: PlacementID,
        fetch: @escaping Fetch,
        parse: @escaping Parse
    ) async -> MainConfiguredPaywall<ProviderPaywall> {
        let main = await loadMain(fetch: fetch, parse: parse)
        guard !Task.isCancelled else {
            return MainConfiguredPaywall(paywall: nil, remoteConfiguration: main.remoteConfiguration)
        }
        let paywall = if placementID == .main {
            main.paywall
        } else {
            await fetch(placementID)
        }
        return MainConfiguredPaywall(paywall: paywall, remoteConfiguration: main.remoteConfiguration)
    }

    private func loadMain(fetch: @escaping Fetch, parse: @escaping Parse) async
        -> MainConfiguredPaywall<ProviderPaywall> {
        if let inFlight {
            return await inFlight.task.value
        }
        sequence &+= 1
        let token = sequence
        let store = store
        let task = Task {
            guard let paywall = await fetch(.main) else {
                // No response is different from a response with a missing key.
                // Never substitute a target placement or retained main flags.
                return MainConfiguredPaywall<ProviderPaywall>(paywall: nil, remoteConfiguration: nil)
            }
            let configuration = await store.resolve(parse(paywall), for: .main)
            return MainConfiguredPaywall(paywall: paywall, remoteConfiguration: configuration)
        }
        inFlight = (token, task)
        let result = await task.value
        if inFlight?.token == token {
            inFlight = nil
        }
        return result
    }
}
