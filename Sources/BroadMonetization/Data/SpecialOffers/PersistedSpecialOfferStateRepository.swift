import BroadCore
import Foundation

/// Compatibility repository for hosts that still migrate former lifecycle
/// snapshots. The standard resolver does not read or write this state.
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

    public init(
        store: any KeyValueStoreProtocol
    ) {
        self.store = store
    }

    public func state(
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
            entry = try await store.read(key)
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
              Self.shouldPersist(snapshot.state),
              Self.isValidPersistedState(snapshot.state)
        else {
            unavailableKeys.insert(key)
            return .unavailable
        }

        guard snapshot.configuration == configuration else {
            do {
                guard try await store.remove(key, ifMatching: entry) else {
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

    public func save(
        _ state: SpecialOfferState,
        for configuration: SpecialOfferConfiguration
    ) async -> Bool {
        let key = Self.storageKey(for: configuration.placementID)
        guard !unavailableKeys.contains(key) else {
            return false
        }
        guard Self.shouldPersist(state), Self.isValidPersistedState(state) else {
            do {
                try await store.remove(key)
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
