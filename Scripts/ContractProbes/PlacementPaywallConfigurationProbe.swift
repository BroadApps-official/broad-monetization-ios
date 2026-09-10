import Foundation

enum MainPaywallConfigurationProbe {
    static func run() async {
        let parser = RemotePaywallConfigurationParser()
        let main: [String: Any] = [
            "ru_pay": true,
            "special_offer": true,
            "auto_revenue_view": true,
            "experiment_code": "main-experiment",
            "segment_code": "main-segment",
            "hardPaywall": true,
            "closeDelay": 5,
            "ui_variant": "main-ui"
        ]
        for value in [true, false, "broken", NSNull()] as [Any] {
            let target: [String: Any] = [
                "ru_pay": value,
                "special_offer": value,
                "auto_revenue_view": false,
                "experiment_code": "target-experiment",
                "segment_code": "target-segment"
            ]
            let resolved = parser.parse(target, fallback: main)
            check(resolved.ruBillingGateDecision == parser.parse(target).ruBillingGateDecision)
            check(resolved.specialOffer == parser.parse(target).specialOffer)
            check(resolved.isAutomaticRevenueViewEnabled == false)
            check(resolved.ruExperiment == parser.parse(target).ruExperiment)
            check(resolved.closeDelay == 5 && resolved.accessPolicy == .hard)
        }
        check(parser.parse([:], fallback: main) == parser.parse(main))
        check(parser.parse(["pay": false], fallback: main).ruBillingGateDecision == .disabled)
        check(parser.parse(["pay": NSNull()], fallback: main).ruBillingGateDecision == .invalid)
        check(parser.parse(["auto_revnue_view": false], fallback: main).isAutomaticRevenueViewEnabled == false)
        check(parser.parse(["segment_code": "partial"], fallback: main).ruExperiment == nil)
        let own = parser.parse(["ru_pay": true, "special_offer": true], fallback: ["ru_pay": false, "special_offer": false])
        check(own.ruBillingGateDecision == .enabled && own.specialOffer?.isEnabled == true)
        await loaderContracts()
        await tokenAliases()
        print("Placement configuration contracts passed: precedence, missing keys, aliases, failures, refresh, concurrency, cancellation.")
    }

    private static func loaderContracts() async {
        let source = ConfigurationProbeSource()
        let loader = PlacementPaywallConfigurationLoader<ConfigurationProbePaywall>(store: .init())
        for placement in [PlacementID.main, .onboarding, .settings, .tokens, .specialOffer] {
            let result = await load(placement, loader: loader, source: source)
            check(result.paywall?.placement == placement)
            check(result.paywall?.products == ["first", "duplicate", "duplicate", "last"])
            check(result.remoteConfiguration?.ruBillingGateDecision == (placement == .main ? .enabled : .disabled))
            check(result.remoteConfiguration?.closeDelay == 5)
        }
        await source.setMainAvailable(false)
        let noMain = await load(.settings, loader: loader, source: source)
        check(noMain.paywall != nil && noMain.remoteConfiguration?.ruBillingGateDecision == .disabled)
        await source.setTargetAvailable(false)
        let neither = await load(.settings, loader: loader, source: source)
        check(neither.paywall == nil && neither.remoteConfiguration == nil)
        await source.setMainAvailable(true)
        let fallback = await load(.settings, loader: loader, source: source)
        check(fallback.paywall == nil && fallback.remoteConfiguration?.ruBillingGateDecision == .enabled)
        let concurrentSource = ConfigurationProbeSource(delay: true)
        let concurrentLoader = PlacementPaywallConfigurationLoader<ConfigurationProbePaywall>(store: .init())
        await withTaskGroup(of: Void.self) { group in
            for index in 0 ..< 24 {
                group.addTask {
                    let result = await load(
                        index.isMultiple(of: 2) ? .settings : .tokens,
                        loader: concurrentLoader,
                        source: concurrentSource
                    )
                    check(result.remoteConfiguration?.ruBillingGateDecision == .disabled)
                }
            }
        }
        await check(concurrentSource.requests.filter { $0 == .main }.count == 1)
        let cancelled = Task { await load(.specialOffer, loader: concurrentLoader, source: concurrentSource) }
        cancelled.cancel()
        await check(cancelled.value.paywall == nil)
        await check(concurrentSource.requests.contains(.specialOffer) == false)
        _ = await load(.settings, loader: concurrentLoader, source: concurrentSource)
        await check(concurrentSource.requests.filter { $0 == .main }.count == 2)
    }

    private static func tokenAliases() async {
        for (configured, alternate) in [("token", "tokens"), ("tokens", "token"), ("Token", "token")] {
            let registry = AdaptyPlacementRegistry(main: .init(rawValue: "main"), mappings: [.tokens: .init(rawValue: configured)])
            let source = PlacementAliasProbeSource(available: alternate)
            let result = await registry.loadPaywall(for: .tokens) { await source.fetch($0) }
            check(result == alternate)
            await check(source.requests == [configured, alternate])
            let exact = PlacementAliasProbeSource(available: configured)
            _ = await registry.loadPaywall(for: .custom("token")) { await exact.fetch($0) }
            await check(exact.requests == [configured])
        }
        for name in ["token", "tokens", "Token", "TOKENS"] {
            check(!PaywallLoadRequest(placementID: .custom(name)).shouldAttemptFallback)
        }
        let custom = AdaptyPlacementRegistry(main: .init(rawValue: "main"), mappings: [.tokens: .init(rawValue: "custom-credits")])
        let missing = PlacementAliasProbeSource(available: "main")
        let result = await custom.loadPaywall(for: .tokens) { await missing.fetch($0) }
        check(result == nil)
        await check(missing.requests == ["custom-credits"])
        let absent = AdaptyPlacementRegistry(main: .init(rawValue: "main"))
        check(!absent.contains(.tokens) && !absent.contains(.custom("token")))
        let singular = AdaptyPlacementRegistry(main: .init(rawValue: "main"), mappings: [.custom("token"): .init(rawValue: "token")])
        check(singular.adaptyPlacement(for: .tokens)?.rawValue == "token")
    }

    private static func load(
        _ placement: PlacementID,
        loader: PlacementPaywallConfigurationLoader<ConfigurationProbePaywall>,
        source: ConfigurationProbeSource
    ) async -> PlacementConfiguredPaywall<ConfigurationProbePaywall> {
        await loader.load(for: placement, fetch: { await source.fetch($0) }, parse: {
            RemotePaywallConfigurationParser().parse($0.dictionary, fallback: $1?.dictionary ?? [:])
        })
    }

    private static func check(_ condition: Bool, line: UInt = #line) {
        precondition(condition, "Placement configuration contract failed at line \(line)")
    }
}

private struct ConfigurationProbePaywall: Sendable {
    let placement: PlacementID
    let products = ["first", "duplicate", "duplicate", "last"]
    var dictionary: [String: Any] {
        placement == .main ? ["ru_pay": true, "special_offer": true, "closeDelay": 5] : ["ru_pay": false, "special_offer": false]
    }
}

private actor ConfigurationProbeSource {
    private var mainAvailable = true
    private var targetAvailable = true
    private let delay: Bool
    private(set) var requests: [PlacementID] = []
    init(delay: Bool = false) {
        self.delay = delay
    }

    func setMainAvailable(_ value: Bool) {
        mainAvailable = value
    }

    func setTargetAvailable(_ value: Bool) {
        targetAvailable = value
    }

    func fetch(_ placement: PlacementID) async -> ConfigurationProbePaywall? {
        requests.append(placement)
        if placement == .main, delay {
            try? await Task.sleep(for: .milliseconds(100))
        }
        return (placement == .main ? mainAvailable : targetAvailable) ? .init(placement: placement) : nil
    }
}

private actor PlacementAliasProbeSource {
    let available: String
    private(set) var requests: [String] = []
    init(available: String) {
        self.available = available
    }

    func fetch(_ candidate: AdaptyPlacementID) -> String? {
        requests.append(candidate.rawValue)
        return candidate.rawValue == available ? available : nil
    }
}
