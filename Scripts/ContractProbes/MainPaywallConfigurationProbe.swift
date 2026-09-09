import Foundation

enum MainPaywallConfigurationProbe {
    static func run() async {
        let placements: [PlacementID] = [.main, .onboarding, .settings, .tokens, .specialOffer]
        for gate in [true, false, "true", "broken"] as [Any] {
            for placement in placements {
                let parser = RemotePaywallConfigurationParser()
                let expected = parser.parse([
                    "ru_pay": gate, "special_offer": gate, "auto_revenue_view": false,
                    "experiment_code": "main-experiment", "segment_code": "main-segment"
                ])
                let source = MainConfigurationProbeSource(main: .init(placement: .main, remote: expected))
                let loader = MainPaywallConfigurationLoader<MainConfigurationProbePaywall>(store: .init())
                let result = await load(placement, loader: loader, source: source)
                check(result.remoteConfiguration == expected)
                check(result.paywall?.placement == placement)
                check(result.paywall?.products == ["first", "duplicate", "duplicate", "last"])
                check(result.paywall?.variation == "variation-\(placement.rawValue)")
                let requests = await source.requests
                check(requests == (placement == .main ? [.main] : [.main, placement]))
            }
        }
        await unavailableAndRefresh()
        await concurrentAndCancelled()
        print(
            "Main configuration contracts passed: five keys, conflicting placements, main reuse, failures, refresh, concurrency, cancellation."
        )
    }

    private static func unavailableAndRefresh() async {
        let parser = RemotePaywallConfigurationParser()
        let source = MainConfigurationProbeSource(main: nil)
        let loader = MainPaywallConfigurationLoader<MainConfigurationProbePaywall>(store: .init())
        let noMain = await load(.settings, loader: loader, source: source)
        check(noMain.paywall?.placement == .settings && noMain.remoteConfiguration == nil)
        let enabled = parser.parse([
            "ru_pay": true, "special_offer": true, "auto_revenue_view": true,
            "experiment_code": "main-experiment", "segment_code": "a"
        ])
        await source.setMain(.init(placement: .main, remote: enabled))
        await check(load(.settings, loader: loader, source: source).remoteConfiguration == enabled)
        await source.setMain(nil)
        await check(load(.tokens, loader: loader, source: source).remoteConfiguration == nil)
        await source.setMain(.init(placement: .main, remote: .empty))
        let missing = await load(.settings, loader: loader, source: source)
        check(missing.remoteConfiguration?.ruBillingGateDecision == .absent)
        check(missing.remoteConfiguration?.specialOffer == nil && missing.remoteConfiguration?.ruExperiment == nil)
        check(missing.remoteConfiguration?.isAutomaticRevenueViewEnabled == true)
        let disabled = parser.parse(["ru_pay": false, "special_offer": false])
        await source.setMain(.init(placement: .main, remote: disabled))
        await source.failTarget()
        let unavailable = await load(.settings, loader: loader, source: source)
        check(unavailable.paywall == nil && unavailable.remoteConfiguration?.ruBillingGateDecision == .disabled)
        check(unavailable.remoteConfiguration?.specialOffer?.isEnabled == false)
        // A different composition has its own main and never inherits flags.
        let other = MainPaywallConfigurationLoader<MainConfigurationProbePaywall>(store: .init())
        let otherSource = MainConfigurationProbeSource(main: .init(placement: .main, remote: .empty))
        await check(load(.settings, loader: other, source: otherSource).remoteConfiguration == .empty)
    }

    private static func concurrentAndCancelled() async {
        let enabled = RemotePaywallConfigurationParser().parse(["ru_pay": true, "special_offer": true])
        let source = MainConfigurationProbeSource(main: .init(placement: .main, remote: enabled), delay: true)
        let loader = MainPaywallConfigurationLoader<MainConfigurationProbePaywall>(store: .init())
        let results = await withTaskGroup(of: MainConfiguredPaywall<MainConfigurationProbePaywall>.self) { group in
            for index in 0 ..< 24 {
                group.addTask {
                    await load(index.isMultiple(of: 2) ? .settings : .tokens, loader: loader, source: source)
                }
            }
            var values: [MainConfiguredPaywall<MainConfigurationProbePaywall>] = []
            for await result in group {
                values.append(result)
            }
            return values
        }
        check(results.count == 24 && results.allSatisfy { $0.remoteConfiguration == enabled && $0.paywall != nil })
        await check(source.requests.filter { $0 == .main }.count == 1)
        let cancelled = Task { await load(.specialOffer, loader: loader, source: source) }
        cancelled.cancel()
        await check(cancelled.value.paywall == nil)
        await check(source.requests.contains(.specialOffer) == false)
        let after = await load(.settings, loader: loader, source: source)
        check(after.remoteConfiguration == enabled && after.paywall != nil)
    }

    private static func load(
        _ placement: PlacementID,
        loader: MainPaywallConfigurationLoader<MainConfigurationProbePaywall>,
        source: MainConfigurationProbeSource
    ) async -> MainConfiguredPaywall<MainConfigurationProbePaywall> {
        await loader.load(for: placement, fetch: { await source.fetch($0) }, parse: { $0.remote })
    }

    private static func check(_ condition: Bool, line: UInt = #line) {
        precondition(condition, "Main configuration contract failed at line \(line)")
    }
}

private struct MainConfigurationProbePaywall: Sendable {
    let placement: PlacementID
    let remote: RemotePaywallConfiguration
    let products = ["first", "duplicate", "duplicate", "last"]
    var variation: String {
        "variation-\(placement.rawValue)"
    }
}

private actor MainConfigurationProbeSource {
    private var main: MainConfigurationProbePaywall?
    private let delay: Bool
    private var targetUnavailable = false
    private(set) var requests: [PlacementID] = []

    init(main: MainConfigurationProbePaywall?, delay: Bool = false) {
        self.main = main
        self.delay = delay
    }

    func setMain(_ value: MainConfigurationProbePaywall?) {
        main = value
    }

    func failTarget() {
        targetUnavailable = true
    }

    func fetch(_ placement: PlacementID) async -> MainConfigurationProbePaywall? {
        requests.append(placement)
        if placement == .main {
            if delay {
                try? await Task.sleep(for: .milliseconds(100))
            }
            return main
        }
        guard !targetUnavailable else { return nil }
        return MainConfigurationProbePaywall(placement: placement, remote: RemotePaywallConfigurationParser().parse([
            "ru_pay": true, "special_offer": true, "auto_revenue_view": true,
            "experiment_code": "wrong-target-experiment", "segment_code": "wrong-target-segment"
        ]))
    }
}
