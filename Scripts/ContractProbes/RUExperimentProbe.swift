import Foundation

@main
enum RUExperimentProbe {
    static func main() async throws {
        try await configurationContracts()
        try catalogContracts()
        await reportingContracts()
        try await RUExperimentHTTPProbe.run()
        print("RU experiment contracts passed: compatibility, fresh config, selection, reporting, authenticated HTTP.")
    }

    static func configurationContracts() async throws {
        let parser = RemotePaywallConfigurationParser()
        let valid = parser.parse(["ru_pay": true, "experiment_code": "fixture", "segment_code": "a"])
        check(valid.ruExperiment != nil)
        for invalid in [true, 7, "", " a", "a\n", String(repeating: "a", count: 65)] as [Any] {
            check(parser.parse(["experiment_code": "fixture", "segment_code": invalid]).ruExperiment == nil)
        }
        check(parser.parse(["experiment_code": "fixture"]).ruExperiment == nil)
        check(RUExperimentMetadata(experimentCode: String(repeating: "a", count: 64), segmentCode: "b") != nil)
        let lastValid = LastValidRemoteConfigurationStore()
        _ = await lastValid.resolve(valid, for: .main)
        let next = await lastValid.resolve(.empty, for: .main)
        check(next.ruExperiment == nil && next.isRUBillingEnabled != true)
        for provenance: PaywallRemoteConfigurationProvenance in [.legacyUnqualified, .platformCache, .providerCacheFallbackPossible] {
            check(payload(remote: valid, provenance: provenance).remoteConfiguration.ruExperiment == nil)
        }
        let fresh = payload(remote: valid)
        check(fresh.remoteConfiguration.ruExperiment != nil)
        let restored = try JSONDecoder().decode(PaywallPayload.self, from: JSONEncoder().encode(fresh))
        check(restored.remoteConfiguration.ruExperiment == nil)
        check(payload(remote: restored.remoteConfiguration, provenance: .platformCache).remoteConfiguration.ruExperiment == nil)
        try check(JSONDecoder().decode(RemotePaywallConfiguration.self, from: Data("{}".utf8)).ruExperiment == nil)
    }

    static func catalogContracts() throws {
        let first = product("first", sku: "sku-a")
        let duplicate = product("second", sku: "sku-a")
        let fallback = product("default", isDefault: true)
        let offer = product("offer", special: true, isDefault: true)
        let catalog = RUCatalogPayload(products: [first, fallback, duplicate, first, offer], fetchedAt: Date())
        let selector = RUExperimentCatalogSelector()
        let selection = selector.select(
            productIDs: [.init(rawValue: "sku-a"), .init(rawValue: "missing")],
            in: catalog,
            kind: .subscriptions
        )
        check(selection.products == [first, duplicate, first] && selection.source == .placementMatches)
        check(selection.missingProductIDs == [.init(rawValue: "missing")])
        let defaults = selector.select(productIDs: [], in: catalog, kind: .subscriptions)
        check(defaults.products == [fallback] && defaults.source == .defaultProducts)
        let legacy = RUCatalogPayload(products: [first, duplicate, first], fetchedAt: Date())
        check(selector.select(productIDs: [], in: legacy, kind: .subscriptions).products == legacy.products)
        check(selector.select(productIDs: [], in: legacy, kind: .specialOffer).products.isEmpty)
        check(selector.select(productIDs: [], in: catalog, kind: .specialOffer).products == [offer])
        check(catalog.products == [first, fallback, duplicate, first, offer])
        let encoded = try JSONEncoder().encode(first)
        var old = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        old.removeValue(forKey: "isDefault")
        try check(!JSONDecoder().decode(RUCatalogProduct.self, from: JSONSerialization.data(withJSONObject: old)).isDefault)
        old["isDefault"] = "malformed-new-field"
        try check(!JSONDecoder().decode(RUCatalogProduct.self, from: JSONSerialization.data(withJSONObject: old)).isDefault)
    }

    static func reportingContracts() async {
        let session = SubjectAuthorizationSession()
        let binding = session.begin(for: .anonymous)
        let repository = RUProbeRepository()
        let tracker = RUBillingExperimentTracker(
            repository: repository, gate: RUBillingGate(isFeatureEnabled: true, deviceContextProvider: RUProbeDevice()),
            storefrontRepository: RUProbeStorefront(), authorizationBinding: binding
        )
        let wall = payload()
        let results = await withTaskGroup(of: RUExperimentTrackingOutcome.self, returning: [RUExperimentTrackingOutcome].self) { group in
            for _ in 0 ..< 30 {
                group.addTask { await tracker.trackShown(wall, placement: "fixture-main") }
            }
            var values: [RUExperimentTrackingOutcome] = []
            for await value in group {
                values.append(value)
            }
            return values
        }
        check(results.allSatisfy { $0 == .reported(requestedSegmentMatches: false) })
        let first = await repository.events
        check(first.count == 2 && first[1].segmentCode == "stored-b")
        await tracker.presentationDidEnd(wall.presentationID)
        _ = await tracker.trackShown(wall, placement: "fixture-main")
        await check(repository.events.count == 2)
        await repository.setFailure(true)
        let failed = payload()
        await check(tracker.trackShown(failed, placement: "fixture-main") == .assignmentFailed)
        await check(tracker.trackShown(failed, placement: "fixture-main") == .assignmentFailed)
        await check(repository.events.count == 3)
        await repository.setFailure(false)
        await check(tracker.trackShown(payload(), placement: "fixture-main") == .reported(requestedSegmentMatches: false))
        let off = payload(remote: RemotePaywallConfigurationParser().parse(["ru_pay": false]))
        await check(tracker.trackShown(off, placement: "fixture-main") == .useAdapty)
        await check(tracker.trackShown(
            payload(remote: RemotePaywallConfigurationParser().parse(["ru_pay": true])),
            placement: "fixture-main"
        ) == .outsideExperiment)
        await check(tracker.trackShown(payload(), placement: "") == .invalidPlacement)
        let closed = payload()
        await tracker.presentationDidEnd(closed.presentationID)
        await check(tracker.trackShown(closed, placement: "fixture-main") == .presentationEnded)
        let beforeLogout = await repository.events.count
        session.invalidate()
        await check(tracker.trackShown(payload(), placement: "fixture-main") == .authorizationUnavailable)
        await check(repository.events.count == beforeLogout)

        let sessionDuringAssign = SubjectAuthorizationSession()
        let invalidating = RUProbeRepository(invalidate: sessionDuringAssign)
        let guarded = RUBillingExperimentTracker(
            repository: invalidating, gate: RUBillingGate(isFeatureEnabled: true, deviceContextProvider: RUProbeDevice()),
            storefrontRepository: RUProbeStorefront(), authorizationBinding: sessionDuringAssign.begin(for: .anonymous)
        )
        await check(guarded.trackShown(payload(), placement: "fixture-main") == .authorizationUnavailable)
        await check(invalidating.events.count == 1)
    }

    static func payload(
        remote: RemotePaywallConfiguration = RemotePaywallConfigurationParser().parse([
            "ru_pay": true, "experiment_code": "fixture", "segment_code": "a"
        ]),
        provenance: PaywallRemoteConfigurationProvenance = .verifiedFreshRemote
    ) -> PaywallPayload {
        PaywallPayload(
            presentationID: .generated(), paywallReference: .init(rawValue: "fixture-paywall"),
            origin: .init(requestedPlacementID: .main, resolvedPlacementID: .main, catalogSource: .adapty),
            products: [], remoteConfiguration: remote, remoteConfigurationProvenance: provenance, fetchedAt: Date()
        )
    }

    static func product(_ id: String, sku: String? = nil, special: Bool = false, isDefault: Bool = false) -> RUCatalogProduct {
        RUCatalogProduct(
            catalogProductID: .init(rawValue: id), kind: .subscription, appStoreProductID: sku.map(ProductID.init(rawValue:)),
            price: nil, displayPrice: nil, subscriptionPeriod: .unknown, supportedMethods: [.card],
            isSpecialOffer: special, isDefault: isDefault
        )
    }
}

struct RUProbeDevice: RUBillingDeviceContextProviderProtocol {
    func currentContext() -> RUBillingDeviceContext {
        .init(regionCode: "RU")
    }
}

struct RUProbeStorefront: StorefrontRepositoryProtocol {
    func currentStorefront() async -> StorefrontResolution {
        .available(.init(countryCode: "US"))
    }
}

actor RUProbeRepository: RUExperimentRepositoryProtocol {
    private(set) var events: [RUExperimentEvent] = []
    private var failure = false
    private let invalidate: SubjectAuthorizationSession?

    init(invalidate: SubjectAuthorizationSession? = nil) {
        self.invalidate = invalidate
    }

    func setFailure(_ value: Bool) {
        failure = value
    }

    func assign(_ event: RUExperimentEvent) async -> RUExperimentAssignOutcome {
        events.append(event)
        await Task.yield()
        invalidate?.invalidate()
        if failure {
            return .unavailable
        }
        return .assigned(.init(
            metadata: RUExperimentMetadata(experimentCode: event.experimentCode, segmentCode: "stored-b")!,
            requestedSegmentMatches: false, isControl: true, created: false
        ))
    }

    func paywallShown(_ event: RUExperimentEvent) async -> RUExperimentShownOutcome {
        events.append(event)
        return .logged
    }
}
