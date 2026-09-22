import BroadCore
import Foundation

/// Durable lifecycle state for the standard 24-hour Special Offer window and
/// its following 24-hour cooldown.
public actor PersistedSpecialOfferStateRepository: SpecialOfferStateRepositoryProtocol {
    private struct Snapshot: Codable, Equatable {
        static let currentSchemaVersion = 1

        let schemaVersion: Int
        let configuration: SpecialOfferConfiguration
        let state: SpecialOfferState

        init(
            configuration: SpecialOfferConfiguration,
            state: SpecialOfferState
        ) {
            schemaVersion = Self.currentSchemaVersion
            self.configuration = configuration
            self.state = state
        }

        var isCurrent: Bool {
            schemaVersion == Self.currentSchemaVersion
        }
    }

    private let store: any KeyValueStoreProtocol
    private var snapshots: [String: Snapshot] = [:]
    private var clearedKeys: Set<String> = []
    private var unavailableKeys: Set<String> = []
    private var pendingOperation: Task<Void, Never>?

    public init(
        store: any KeyValueStoreProtocol
    ) {
        self.store = store
    }

    public func state(
        for configuration: SpecialOfferConfiguration
    ) async -> SpecialOfferStateLoadOutcome {
        await serialized { await self.loadState(for: configuration) }
    }

    public func save(
        _ state: SpecialOfferState,
        for configuration: SpecialOfferConfiguration
    ) async -> Bool {
        await serialized { await self.saveState(state, for: configuration) }
    }

    private func serialized<Value: Sendable>(
        _ operation: @escaping @Sendable () async -> Value
    ) async -> Value {
        let previous = pendingOperation
        let task = Task {
            await previous?.value
            return await operation()
        }
        pendingOperation = Task { _ = await task.value }
        return await task.value
    }

    private func loadState(
        for configuration: SpecialOfferConfiguration
    ) async -> SpecialOfferStateLoadOutcome {
        let key = Self.storageKey(for: configuration.placementID)
        guard !unavailableKeys.contains(key) else {
            return .unavailable
        }
        if let snapshot = snapshots[key], snapshot.configuration == configuration {
            return .loaded(snapshot.state)
        }
        if clearedKeys.contains(key) {
            return .loaded(.eligible)
        }

        let entry: KeyValueStoreEntry
        do {
            entry = try await readMigratingLegacyState(for: configuration, key: key)
        } catch {
            unavailableKeys.insert(key)
            return .unavailable
        }

        guard entry != .missing else {
            clearedKeys.insert(key)
            return .loaded(.eligible)
        }

        guard case let .data(data) = entry,
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
              snapshot.isCurrent,
              Self.shouldPersist(snapshot.state) || (Self.isCanonical(configuration) && snapshot.state == .eligible),
              Self.isValidPersistedState(snapshot.state)
        else {
            unavailableKeys.insert(key)
            return .unavailable
        }

        guard snapshot.configuration == configuration else {
            do {
                guard try await reset(configuration: configuration, key: key, ifMatching: entry) else {
                    unavailableKeys.insert(key)
                    return .unavailable
                }
            } catch {
                unavailableKeys.insert(key)
                return .unavailable
            }
            snapshots[key] = nil
            clearedKeys.insert(key)
            return .loaded(.eligible)
        }

        snapshots[key] = snapshot
        return .loaded(snapshot.state)
    }

    private func saveState(
        _ state: SpecialOfferState,
        for configuration: SpecialOfferConfiguration
    ) async -> Bool {
        let key = Self.storageKey(for: configuration.placementID)
        guard !unavailableKeys.contains(key) else {
            return false
        }
        guard Self.shouldPersist(state), Self.isValidPersistedState(state) else {
            do {
                if Self.isCanonical(configuration) {
                    let marker = Snapshot(configuration: configuration, state: .eligible)
                    try await store.write(JSONEncoder().encode(marker), forKey: key)
                } else {
                    try await store.remove(key)
                }
            } catch {
                unavailableKeys.insert(key)
                return false
            }
            snapshots[key] = nil
            clearedKeys.insert(key)
            return true
        }

        let snapshot = Snapshot(configuration: configuration, state: state)
        guard let data = try? JSONEncoder().encode(snapshot) else {
            unavailableKeys.insert(key)
            return false
        }

        do {
            try await store.write(data, forKey: key)
        } catch {
            unavailableKeys.insert(key)
            return false
        }
        snapshots[key] = snapshot
        clearedKeys.remove(key)
        return true
    }
}

private extension PersistedSpecialOfferStateRepository {
    static func isCanonical(_ configuration: SpecialOfferConfiguration) -> Bool {
        configuration.placementID.rawValue == "special_offer"
    }

    /// The new key wins. Keep a durable eligible marker after reset so an old
    /// snapshot cannot resurrect a completed cycle on the next application launch.
    func reset(
        configuration: SpecialOfferConfiguration, key: String, ifMatching entry: KeyValueStoreEntry
    ) async throws -> Bool {
        guard Self.isCanonical(configuration) else {
            return try await store.remove(key, ifMatching: entry)
        }
        let marker = Snapshot(configuration: configuration, state: .eligible)
        return try await store.write(JSONEncoder().encode(marker), forKey: key, ifMatching: entry)
    }

    func readMigratingLegacyState(
        for configuration: SpecialOfferConfiguration, key: String
    ) async throws -> KeyValueStoreEntry {
        let current = try await store.read(key)
        guard current == .missing, Self.isCanonical(configuration) else { return current }
        let legacyKey = Self.storageKey(for: PlacementID(rawValue: "special-offer"))
        let legacyEntry = try await store.read(legacyKey)
        guard legacyEntry != .missing else { return .missing }
        guard case let .data(data) = legacyEntry,
              let legacy = try? JSONDecoder().decode(Snapshot.self, from: data),
              legacy.isCurrent, Self.shouldPersist(legacy.state), Self.isValidPersistedState(legacy.state),
              legacy.configuration.placementID.rawValue == "special-offer" else {
            throw SpecialOfferMigrationError.invalidLegacyState
        }
        let migratedConfiguration = SpecialOfferConfiguration(
            placementID: configuration.placementID, gatePlacementID: legacy.configuration.gatePlacementID,
            windowDuration: legacy.configuration.windowDuration, cooldownDuration: legacy.configuration.cooldownDuration
        )
        let migrated = Snapshot(
            configuration: configuration,
            state: migratedConfiguration == configuration ? legacy.state : .eligible
        )
        let encoded = try JSONEncoder().encode(migrated)
        if try await store.write(encoded, forKey: key, ifMatching: .missing) {
            return .data(encoded)
        }
        // A concurrent writer installed the canonical state. Read its result;
        // never overwrite it with the older placement's timestamps.
        let winner = try await store.read(key)
        guard winner != .missing else { throw SpecialOfferMigrationError.concurrentReset }
        return winner
    }

    static func storageKey(
        for placementID: PlacementID
    ) -> String {
        let rawValue = placementID.rawValue
        return "special-offer-state.v1.\(rawValue.utf8.count)#\(rawValue)"
    }

    static func shouldPersist(
        _ state: SpecialOfferState
    ) -> Bool {
        switch state {
        case .active, .expired, .cooldown:
            true
        case .unavailable, .eligible:
            false
        }
    }

    static func isValidPersistedState(
        _ state: SpecialOfferState
    ) -> Bool {
        switch state {
        case let .active(window):
            window.startedAt.timeIntervalSinceReferenceDate.isFinite
                && window.expiresAt.timeIntervalSinceReferenceDate.isFinite
                && window.expiresAt > window.startedAt
        case let .expired(date), let .cooldown(date):
            date.timeIntervalSinceReferenceDate.isFinite
        case .unavailable, .eligible:
            true
        }
    }
}

private enum SpecialOfferMigrationError: Error {
    case invalidLegacyState
    case concurrentReset
}
