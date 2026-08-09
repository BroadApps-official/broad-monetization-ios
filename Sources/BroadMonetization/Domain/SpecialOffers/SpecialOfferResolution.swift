import Foundation

public struct SpecialOfferCountdownAuthorization: Equatable, Sendable {
    public let expiresAt: Date
    private let deadline: ContinuousClock.Instant

    init?(
        expiresAt: Date,
        trustedTime: SpecialOfferTrustedTime
    ) {
        let remaining = expiresAt.timeIntervalSince(trustedTime.date)
        guard SpecialOfferDurationPolicy.isValid(remaining) else {
            return nil
        }
        let capturedDeadline = trustedTime.observedAt.advanced(by: .seconds(remaining))
        guard ContinuousClock().now < capturedDeadline else {
            return nil
        }
        self.expiresAt = expiresAt
        deadline = capturedDeadline
    }

    /// Remaining time is based on a monotonic clock and cannot be extended by
    /// changing the device wall clock after the offer was authorized.
    public var remainingTimeInterval: TimeInterval {
        let components = ContinuousClock().now.duration(to: deadline).components
        return Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }

    public var isExpired: Bool {
        ContinuousClock().now >= deadline
    }

    public func sleepUntilExpiration() async throws {
        try await ContinuousClock().sleep(until: deadline)
    }
}

public struct SpecialOfferPresentationAuthorization: Equatable, Sendable {
    public let paywallPresentationID: PaywallPresentationID
    public let countdown: SpecialOfferCountdownAuthorization?

    /// Server-time value for diagnostics and copy only. Runtime expiry and UI
    /// countdown must use `countdown`'s monotonic deadline.
    public var expiresAt: Date? {
        countdown?.expiresAt
    }
}

public struct SpecialOfferResolution: Equatable, Sendable {
    public let state: SpecialOfferState
    public let paywall: PaywallPayload?
    public let presentationAuthorization: SpecialOfferPresentationAuthorization?

    public init(
        state: SpecialOfferState,
        paywall: PaywallPayload?,
        trustedTime: SpecialOfferTrustedTime? = nil
    ) {
        let authorization: SpecialOfferPresentationAuthorization?
        switch state {
        case .eligible:
            precondition(
                paywall != nil,
                "A presentable special offer requires its paywall payload"
            )
            authorization = Self.makeAuthorization(
                paywall: paywall,
                countdown: nil
            )
        case let .active(window):
            precondition(
                paywall != nil,
                "A presentable special offer requires its paywall payload"
            )
            guard let trustedTime,
                  trustedTime.date >= window.startedAt,
                  trustedTime.date < window.expiresAt
            else {
                self.state = .unavailable(.untrustedTime)
                self.paywall = nil
                presentationAuthorization = nil
                return
            }
            guard let countdown = SpecialOfferCountdownAuthorization(
                expiresAt: window.expiresAt,
                trustedTime: trustedTime
            ) else {
                // Corrupt legacy persistence or an unsafe clock range must not
                // reach `Duration.seconds` or make the campaign presentable.
                self.state = .unavailable(.untrustedTime)
                self.paywall = nil
                presentationAuthorization = nil
                return
            }
            authorization = Self.makeAuthorization(
                paywall: paywall,
                countdown: countdown
            )
        case .unavailable, .expired, .cooldown:
            precondition(
                paywall == nil,
                "An unavailable special offer must not carry a paywall payload"
            )
            authorization = nil
        }

        self.state = state
        self.paywall = paywall
        presentationAuthorization = authorization
    }

    private static func makeAuthorization(
        paywall: PaywallPayload?,
        countdown: SpecialOfferCountdownAuthorization?
    ) -> SpecialOfferPresentationAuthorization {
        guard let paywall,
              paywall.remoteConfigurationProvenance.authorizesTimeSensitiveFeatures,
              paywall.remoteConfiguration.specialOffer?.isEnabled == true
        else {
            preconditionFailure(
                "Special-offer presentation requires an explicitly enabled verified payload"
            )
        }
        return SpecialOfferPresentationAuthorization(
            paywallPresentationID: paywall.presentationID,
            countdown: countdown
        )
    }
}
