import BroadCore
import Foundation

public struct PendingRUCheckoutContext: Codable, Equatable, Sendable {
    public let checkoutSessionID: CheckoutSessionID
    public let attemptID: MonetizationAttemptID
    public let productID: RUCatalogProductID
    public let checkoutMethod: CheckoutMethod
    public let paywallPresentationID: PaywallPresentationID?
    public let paywallVariationID: PaywallVariationID?
    public let requestedPlacementID: PlacementID?
    public let resolvedPlacementID: PlacementID?
    public let startedAt: Date
    public let expiresAt: Date?
    public let accountExpectation: RUAccountCheckoutExpectation?

    public init(
        checkoutSessionID: CheckoutSessionID,
        attemptID: MonetizationAttemptID,
        productID: RUCatalogProductID,
        checkoutMethod: CheckoutMethod,
        paywallPresentationID: PaywallPresentationID? = nil,
        paywallVariationID: PaywallVariationID? = nil,
        requestedPlacementID: PlacementID? = nil,
        resolvedPlacementID: PlacementID? = nil,
        startedAt: Date,
        expiresAt: Date?,
        accountExpectation: RUAccountCheckoutExpectation? = nil
    ) {
        precondition(
            checkoutMethod == .sbp || checkoutMethod == .card,
            "Pending RU checkout supports only SBP or card"
        )
        precondition(startedAt.timeIntervalSinceReferenceDate.isFinite, "Pending checkout start date must be finite")
        precondition(expiresAt?.timeIntervalSinceReferenceDate.isFinite != false, "Pending checkout expiration must be finite")
        precondition(expiresAt.map { $0 > startedAt } ?? true, "Pending checkout expiration must follow its start")
        let hasCompletePaywallOrigin = paywallPresentationID != nil
            && requestedPlacementID != nil
            && resolvedPlacementID != nil
        let hasNoPaywallOrigin = paywallPresentationID == nil
            && requestedPlacementID == nil
            && resolvedPlacementID == nil
        precondition(
            hasCompletePaywallOrigin || hasNoPaywallOrigin,
            "Pending RU checkout requires a complete paywall origin"
        )
        precondition(
            paywallVariationID == nil || paywallPresentationID != nil,
            "Pending RU checkout variation requires a paywall presentation"
        )

        self.checkoutSessionID = checkoutSessionID
        self.attemptID = attemptID
        self.productID = productID
        self.checkoutMethod = checkoutMethod
        self.paywallPresentationID = paywallPresentationID
        self.paywallVariationID = paywallVariationID
        self.requestedPlacementID = requestedPlacementID
        self.resolvedPlacementID = resolvedPlacementID
        self.startedAt = startedAt
        self.expiresAt = expiresAt
        self.accountExpectation = accountExpectation
    }

    public init(from decoder: any Decoder) throws {
        let value = try DecodedPendingRUCheckoutContext(from: decoder)
        guard MonetizationIdentifierPolicy.isValid(value.checkoutSessionID.rawValue),
              MonetizationIdentifierPolicy.isValid(value.attemptID.rawValue),
              MonetizationIdentifierPolicy.isValid(value.productID.rawValue),
              value.checkoutMethod == .sbp || value.checkoutMethod == .card,
              Self.hasValidPaywallOrigin(
                  presentationID: value.paywallPresentationID,
                  variationID: value.paywallVariationID,
                  requestedPlacementID: value.requestedPlacementID,
                  resolvedPlacementID: value.resolvedPlacementID
              ),
              value.startedAt.timeIntervalSinceReferenceDate.isFinite,
              value.expiresAt?.timeIntervalSinceReferenceDate.isFinite != false,
              value.expiresAt.map({ $0 > value.startedAt }) ?? true
        else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid persisted RU checkout context"
                )
            )
        }

        self.init(
            checkoutSessionID: CheckoutSessionID(
                rawValue: value.checkoutSessionID.rawValue
            ),
            attemptID: MonetizationAttemptID(rawValue: value.attemptID.rawValue),
            productID: RUCatalogProductID(rawValue: value.productID.rawValue),
            checkoutMethod: value.checkoutMethod,
            paywallPresentationID: value.paywallPresentationID,
            paywallVariationID: value.paywallVariationID,
            requestedPlacementID: value.requestedPlacementID,
            resolvedPlacementID: value.resolvedPlacementID,
            startedAt: value.startedAt,
            expiresAt: value.expiresAt,
            accountExpectation: value.accountExpectation
        )
    }

    public var analyticsContext: RUCheckoutAnalyticsContext {
        RUCheckoutAnalyticsContext(
            attemptID: attemptID,
            productID: productID,
            checkoutMethod: checkoutMethod,
            paywallPresentationID: paywallPresentationID,
            paywallVariationID: paywallVariationID,
            requestedPlacementID: requestedPlacementID,
            resolvedPlacementID: resolvedPlacementID
        )
    }

    private static func hasValidPaywallOrigin(
        presentationID: PaywallPresentationID?,
        variationID: PaywallVariationID?,
        requestedPlacementID: PlacementID?,
        resolvedPlacementID: PlacementID?
    ) -> Bool {
        let hasCompleteOrigin = presentationID != nil
            && requestedPlacementID != nil
            && resolvedPlacementID != nil
        let hasNoOrigin = presentationID == nil
            && requestedPlacementID == nil
            && resolvedPlacementID == nil
        return (hasCompleteOrigin || hasNoOrigin)
            && (variationID == nil || presentationID != nil)
    }
}

private struct DecodedPendingRUCheckoutContext: Decodable {
    let accountExpectation: RUAccountCheckoutExpectation?
    let checkoutSessionID: CheckoutSessionID
    let attemptID: MonetizationAttemptID
    let productID: RUCatalogProductID
    let checkoutMethod: CheckoutMethod
    let paywallPresentationID: PaywallPresentationID?
    let paywallVariationID: PaywallVariationID?
    let requestedPlacementID: PlacementID?
    let resolvedPlacementID: PlacementID?
    let startedAt: Date
    let expiresAt: Date?
}
