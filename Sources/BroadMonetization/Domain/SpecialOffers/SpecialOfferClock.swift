import Foundation

/// A trusted wall-clock value paired with the monotonic instant at which the
/// host observed it. The pair prevents network and persistence work from
/// extending an already running offer window.
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

/// A clock reading that can either authorize the timed contract or fail closed.
public enum SpecialOfferClockReading: Equatable, Sendable {
    case synchronized(SpecialOfferTrustedTime)
    case untrusted

    /// Captures a finite server-synchronized date and its monotonic anchor.
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

/// Host boundary for server-synchronized Special Offer time.
///
/// The standard resolver fails closed while time is untrusted. A host normally
/// creates this value from BroadCore's `ServerTimeProviderProtocol` after
/// recording a backend `Date` header.
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
