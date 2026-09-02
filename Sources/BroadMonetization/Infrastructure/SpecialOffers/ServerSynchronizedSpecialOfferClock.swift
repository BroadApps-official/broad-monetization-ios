import BroadCore
import Foundation

/// Trusted time for a timed special offer, derived from the `Date` header of the
/// host's own backend answers instead of the device clock.
///
/// A timed offer must not run on the device clock: the user can move it forward
/// to end a campaign early, or back to extend one that is over. Every backend
/// answer carries a `Date` header, so the host learns server time from calls it
/// already makes; the host feeds each server `Date` to ``record(_:)`` and the gap
/// to the device clock is kept and applied to every reading.
///
/// The gap is persisted, because a window outlives the process that opened it: a
/// relaunch two hours in must still see two hours. Offline the device clock is all
/// there is, but never backwards: a reading earlier than one already seen is
/// refused, so winding the clock back buys nothing.
///
/// Bridge it into the resolver with ``makeSpecialOfferClock()``.
public actor ServerSynchronizedSpecialOfferClock {
    private struct Persisted: Codable, Equatable {
        var offset: TimeInterval?
        var highWater: TimeInterval?
    }

    /// How far a reading must advance before the new mark is persisted. Writing
    /// every read would mean a store write per frame of the countdown.
    private static let highWaterPersistStep: TimeInterval = 60
    private static let storageKey = "special-offer.server-clock.v1"

    private let store: any KeyValueStoreProtocol
    private let deviceNow: @Sendable () -> Date

    private var loaded = false
    private var offset: TimeInterval?
    private var highWater = Date.distantPast
    private var persistedHighWater = Date.distantPast

    public init(
        store: any KeyValueStoreProtocol,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        deviceNow = now
    }

    /// Records a trusted server `Date`, typically from a response `Date` header.
    /// Non-finite dates are ignored.
    public func record(_ date: Date) async {
        guard date.timeIntervalSinceReferenceDate.isFinite else {
            return
        }
        await ensureLoaded()

        offset = date.timeIntervalSince(deviceNow())
        // A server that says the app is later than it thought is still the
        // authority: the mark follows it down rather than freezing time.
        if date < highWater {
            highWater = date
            persistedHighWater = date
        }
        await persist()
    }

    /// Whether any server answer has set the offset yet.
    public func isSynchronized() async -> Bool {
        await ensureLoaded()
        return offset != nil
    }

    /// The current reading. `.synchronized` once a server answer has set the
    /// offset, monotonically non-decreasing; `.untrusted` before then, so a timed
    /// offer fails closed until the server has spoken.
    public func reading() async -> SpecialOfferClockReading {
        await ensureLoaded()
        guard let offset else {
            return .untrusted
        }

        let candidate = deviceNow().addingTimeInterval(offset)
        let value: Date
        if candidate > highWater {
            highWater = candidate
            value = candidate
            if candidate.timeIntervalSince(persistedHighWater) >= Self.highWaterPersistStep {
                persistedHighWater = candidate
                await persist()
            }
        } else {
            value = highWater
        }
        return .trusted(value)
    }

    /// A ``SpecialOfferClock`` backed by this clock, for the timed
    /// ``ResolveSpecialOfferUseCase`` initializer.
    public nonisolated func makeSpecialOfferClock() -> SpecialOfferClock {
        SpecialOfferClock { await self.reading() }
    }

    private func ensureLoaded() async {
        guard !loaded else {
            return
        }
        loaded = true

        guard case let .data(data) = await (try? store.read(Self.storageKey)) ?? .missing,
              let persisted = try? JSONDecoder().decode(Persisted.self, from: data)
        else {
            return
        }
        offset = persisted.offset
        if let mark = persisted.highWater {
            let date = Date(timeIntervalSinceReferenceDate: mark)
            highWater = date
            persistedHighWater = date
        }
    }

    private func persist() async {
        let persisted = Persisted(
            offset: offset,
            highWater: highWater == .distantPast
                ? nil
                : highWater.timeIntervalSinceReferenceDate
        )
        guard let data = try? JSONEncoder().encode(persisted) else {
            return
        }
        try? await store.write(data, forKey: Self.storageKey)
    }
}

/// Reads the `Date` header of an HTTP answer into a `Date` a host can feed to
/// ``ServerSynchronizedSpecialOfferClock/record(_:)``.
public enum HTTPServerDate {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()

    public static func date(from response: HTTPURLResponse) -> Date? {
        guard let header = response.value(forHTTPHeaderField: "Date") else {
            return nil
        }
        return formatter.date(from: header)
    }
}
