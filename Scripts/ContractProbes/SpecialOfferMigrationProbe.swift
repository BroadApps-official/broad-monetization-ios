import BroadCore
import Foundation

@main
enum SpecialOfferMigrationProbe {
    static let legacy = SpecialOfferConfiguration(placementID: .init(rawValue: "special-offer"))
    static let canonical = SpecialOfferConfiguration(placementID: .specialOffer)
    static let start = Date(timeIntervalSince1970: 1_700_000_000)
    static let cooldown = SpecialOfferState.cooldown(until: start.addingTimeInterval(172_800))

    static func main() async {
        for state: SpecialOfferState in [
            .active(.init(startedAt: start, expiresAt: start.addingTimeInterval(86400))),
            cooldown, .expired(date: start.addingTimeInterval(86400))
        ] {
            await preservesDatesAndReset(state)
        }
        await canonicalWins()
        await storageFailures()
        await unrelatedConfiguration()
        await resetBeforeMigration()
        print("PASS: Special Offer placement migration preserves dates, cooldown and reset; canonical state wins; storage fails closed.")
    }

    static func preservesDatesAndReset(_ state: SpecialOfferState) async {
        let store = MemoryStore()
        let repository = PersistedSpecialOfferStateRepository(store: store)
        await check(repository.save(state, for: legacy))
        await check(repository.state(for: canonical) == .loaded(state))
        let restarted = PersistedSpecialOfferStateRepository(store: store)
        await check(restarted.state(for: canonical) == .loaded(state))
        await check(restarted.save(.eligible, for: canonical))
        let afterReset = PersistedSpecialOfferStateRepository(store: store)
        await check(afterReset.state(for: canonical) == .loaded(.eligible))
        // Old app data still exists, but must never resurrect the cycle.
        await check(afterReset.state(for: legacy) == .loaded(state))
    }

    static func canonicalWins() async {
        let store = MemoryStore()
        let repository = PersistedSpecialOfferStateRepository(store: store)
        await check(repository.save(cooldown, for: legacy))
        let newer = SpecialOfferState.cooldown(until: start.addingTimeInterval(259_200))
        await check(repository.save(newer, for: canonical))
        await check(PersistedSpecialOfferStateRepository(store: store).state(for: canonical) == .loaded(newer))
        // Simulate a second repository winning the insert between read and CAS.
        let canonicalData = await store.read(key(canonical))
        await store.remove(key(canonical))
        await store.installBeforeNextInsert(canonicalData)
        await check(PersistedSpecialOfferStateRepository(store: store).state(for: canonical) == .loaded(newer))
    }

    static func storageFailures() async {
        let store = MemoryStore()
        await check(PersistedSpecialOfferStateRepository(store: store).save(cooldown, for: legacy))
        await store.failWrites(true)
        await check(PersistedSpecialOfferStateRepository(store: store).state(for: canonical) == .unavailable)
        await check(store.read(key(canonical)) == .missing)
        await store.failWrites(false)
        await check(PersistedSpecialOfferStateRepository(store: store).state(for: canonical) == .loaded(cooldown))
        await store.remove(key(canonical))
        try? await store.write(Data("invalid".utf8), forKey: key(legacy))
        await check(PersistedSpecialOfferStateRepository(store: store).state(for: canonical) == .unavailable)
        await check(store.read(key(canonical)) == .missing)
    }

    static func unrelatedConfiguration() async {
        let store = MemoryStore()
        let old = SpecialOfferConfiguration(placementID: legacy.placementID, gatePlacementID: .onboarding)
        await check(PersistedSpecialOfferStateRepository(store: store).save(cooldown, for: old))
        await check(PersistedSpecialOfferStateRepository(store: store).state(for: canonical) == .loaded(.eligible))
        let custom = SpecialOfferConfiguration(placementID: .custom("another-offer"))
        await check(PersistedSpecialOfferStateRepository(store: store).state(for: custom) == .loaded(.eligible))
        let changed = SpecialOfferConfiguration(placementID: .specialOffer, gatePlacementID: .onboarding)
        await check(PersistedSpecialOfferStateRepository(store: store).state(for: changed) == .loaded(.eligible))
        await check(PersistedSpecialOfferStateRepository(store: store).state(for: canonical) == .loaded(.eligible))
    }

    static func resetBeforeMigration() async {
        let store = MemoryStore()
        let repository = PersistedSpecialOfferStateRepository(store: store)
        await check(repository.save(cooldown, for: legacy))
        await check(repository.save(.eligible, for: canonical))
        await check(PersistedSpecialOfferStateRepository(store: store).state(for: canonical) == .loaded(.eligible))
        await store.remove(key(canonical))
        let concurrent = PersistedSpecialOfferStateRepository(store: store)
        async let read = concurrent.state(for: canonical)
        async let reset = concurrent.save(.eligible, for: canonical)
        _ = await read
        await check(reset)
        await check(PersistedSpecialOfferStateRepository(store: store).state(for: canonical) == .loaded(.eligible))
    }

    static func key(_ configuration: SpecialOfferConfiguration) -> String {
        let value = configuration.placementID.rawValue
        return "special-offer-state.v1.\(value.utf8.count)#\(value)"
    }

    static func check(_ value: Bool, line: UInt = #line) {
        precondition(value, "Special Offer migration failed at \(line)")
    }
}

private actor MemoryStore: KeyValueStoreProtocol {
    var entries: [String: Data] = [:]
    var writesFail = false
    var concurrentEntry: KeyValueStoreEntry?

    func installBeforeNextInsert(_ entry: KeyValueStoreEntry) {
        concurrentEntry = entry
    }

    func failWrites(_ value: Bool) {
        writesFail = value
    }

    func read(_ key: String) -> KeyValueStoreEntry {
        entries[key].map(KeyValueStoreEntry.data) ?? .missing
    }

    func write(_ data: Data, forKey key: String) throws {
        if writesFail {
            throw CacheRepositoryError.encodingFailed
        }
        entries[key] = data
    }

    func write(_ data: Data, forKey key: String, ifMatching snapshot: KeyValueStoreEntry) throws -> Bool {
        if snapshot == .missing, case let .data(winner) = concurrentEntry {
            entries[key] = winner
            concurrentEntry = nil
        }
        guard read(key) == snapshot else { return false }
        try write(data, forKey: key)
        return true
    }

    func remove(_ key: String) {
        entries[key] = nil
    }

    func remove(_ key: String, ifMatching snapshot: KeyValueStoreEntry) -> Bool {
        guard read(key) == snapshot else { return false }
        remove(key)
        return true
    }
}
