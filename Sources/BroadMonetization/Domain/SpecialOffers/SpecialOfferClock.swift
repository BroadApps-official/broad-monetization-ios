import Foundation

/// Compatibility value retained for hosts compiled against the former timed
/// Special Offer API. The standard resolver and visual countdown ignore it.
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

/// Compatibility reading retained for the former timed Special Offer API.
public enum SpecialOfferClockReading: Equatable, Sendable {
    case synchronized(SpecialOfferTrustedTime)
    case untrusted

    /// Wraps a finite legacy date. This value does not authorize presentation.
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

/// Compatibility boundary retained for the former timed Special Offer API.
/// The standard resolver ignores this clock: only `special_offer = true` from
/// the current provider payload authorizes presentation.
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
