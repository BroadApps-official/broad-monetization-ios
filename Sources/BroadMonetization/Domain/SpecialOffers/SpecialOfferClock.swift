import Foundation

/// A trusted wall-clock value paired with the monotonic instant at which the
/// host observed it. Keeping the pair prevents async persistence/network work
/// from extending a countdown after the trusted reading was captured.
public struct SpecialOfferTrustedTime: Equatable, Sendable {
    public let date: Date
    let observedAt: ContinuousClock.Instant

    fileprivate init(
        date: Date,
        observedAt: ContinuousClock.Instant
    ) {
        self.date = date
        self.observedAt = observedAt
    }
}

/// A wall-clock reading that the host either obtained from a trusted remote
/// source or could not verify. Device `Date()` must never be promoted through
/// `trusted(_:)`: users can change it and extend a persisted timed offer.
public enum SpecialOfferClockReading: Equatable, Sendable {
    case synchronized(SpecialOfferTrustedTime)
    case untrusted

    /// Capture this immediately when a trusted server-synchronized Date is
    /// available. The monotonic instant travels with the value across awaits.
    public static func trusted(_ date: Date) -> SpecialOfferClockReading {
        guard date.timeIntervalSinceReferenceDate.isFinite else {
            return .untrusted
        }
        return .synchronized(
            SpecialOfferTrustedTime(
                date: date,
                observedAt: ContinuousClock().now
            )
        )
    }
}

/// Host boundary for server-synchronized special-offer time.
///
/// The default is deliberately fail-closed. Apps that use timed offers must
/// inject a provider backed by trusted server time or a rollback-detecting
/// synchronization layer. Untimed offers do not consult this clock.
public struct SpecialOfferClock: Sendable {
    private let readingProvider: @Sendable () async -> SpecialOfferClockReading

    public init(
        reading: @escaping @Sendable () async -> SpecialOfferClockReading
    ) {
        readingProvider = reading
    }

    public func reading() async -> SpecialOfferClockReading {
        await readingProvider()
    }

    public static let untrusted = SpecialOfferClock {
        .untrusted
    }
}
