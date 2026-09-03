import BroadCore
import Foundation

/// Stores the current offer as a single timestamp — the server time at which it
/// began — through ``KeyValueStoreProtocol``.
///
/// One value is enough, because ``SpecialOfferCadence`` derives both boundaries
/// from it. This type adds only the read and the write: a window that starts is
/// persisted before it is handed out, and a window that cannot be written is
/// refused rather than shown and forgotten.
public actor PersistedSpecialOfferWindowStore:
    SpecialOfferWindowStoreProtocol {
    private struct State: Codable, Equatable {
        let startedAt: Date
    }

    public static let defaultStorageKey = "broadmonetization.special-offer-campaign.window.v1"

    private let store: any KeyValueStoreProtocol
    private let storageKey: String
    private let cadence = SpecialOfferCadence()

    /// The decision reads the stored start and then writes a new one, with a
    /// suspension in between. Left unserialized, two callers could both read
    /// "nothing stored" and both open a window, so one day's offer would be
    /// spent twice. Each decision waits for the previous one instead.
    private var pendingDecision: Task<SpecialOfferCampaignWindowDecision, Never>?

    public init(
        store: any KeyValueStoreProtocol,
        storageKey: String = PersistedSpecialOfferWindowStore.defaultStorageKey
    ) {
        precondition(!storageKey.isEmpty, "Special-offer window storage key must not be empty")
        self.store = store
        self.storageKey = storageKey
    }

    public func windowForPresentation(
        now: Date,
        windowDuration: TimeInterval,
        cooldownDuration: TimeInterval
    ) async -> SpecialOfferCampaignWindowDecision {
        let previous = pendingDecision
        let decision = Task { [self] in
            _ = await previous?.value
            return await decide(
                now: now,
                windowDuration: windowDuration,
                cooldownDuration: cooldownDuration
            )
        }
        pendingDecision = decision
        return await decision.value
    }

    public func clear() async {
        // A purchase that ends the campaign must not be overtaken by a decision
        // that was already opening a window for it.
        _ = await pendingDecision?.value
        try? await store.remove(storageKey)
    }

    private func decide(
        now: Date,
        windowDuration: TimeInterval,
        cooldownDuration: TimeInterval
    ) async -> SpecialOfferCampaignWindowDecision {
        switch await cadence.decision(
            startedAt: storedStart(),
            now: now,
            windowDuration: windowDuration,
            cooldownDuration: cooldownDuration
        ) {
        case let .live(window):
            return .open(window)
        case let .starts(window):
            guard await save(startedAt: window.startedAt) else {
                return .unwritable
            }
            return .open(window)
        case let .cooldown(until):
            return .cooldown(until: until)
        }
    }

    private func storedStart() async -> Date? {
        guard case let .data(data) = await (try? store.read(storageKey)) ?? .missing,
              let state = try? JSONDecoder().decode(State.self, from: data),
              state.startedAt.timeIntervalSinceReferenceDate.isFinite
        else {
            return nil
        }
        return state.startedAt
    }

    private func save(startedAt: Date) async -> Bool {
        guard let data = try? JSONEncoder().encode(State(startedAt: startedAt)) else {
            return false
        }
        do {
            try await store.write(data, forKey: storageKey)
            return true
        } catch {
            return false
        }
    }
}
