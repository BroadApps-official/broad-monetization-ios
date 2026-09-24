import Foundation

/// A support-safe account of an Apple purchase attempt. It is diagnostic only:
/// it neither proves a charge nor authorizes access or another purchase.
public struct PendingPurchaseDiagnostic: Equatable, Sendable {
    public enum Kind: String, Codable, Equatable, Sendable {
        case premium
        case consumable
    }

    public enum Stage: String, Codable, Equatable, Sendable {
        case started
        case providerPending
        case outcomeUnknown
        case transactionNotFound
        case storeUnavailable
        case transactionVerified
        case entitlementAwaitingConfirmation
        case backendPending
        case backendUnavailable
        case accountMismatch
        case localRecordMissing
        case localStoreUnavailable
    }

    public let attemptID: MonetizationAttemptID
    public let productID: ProductID
    public let requestedPlacementID: PlacementID
    public let resolvedPlacementID: PlacementID
    public let paywallVariationID: PaywallVariationID?
    public let kind: Kind
    public let startedAt: Date
    public let lastCheckedAt: Date?
    public let stage: Stage
    public let diagnosticCode: String?
    public let isPendingLocally: Bool
    public let reviewRequired: Bool

    public init(
        attemptID: MonetizationAttemptID,
        productID: ProductID,
        requestedPlacementID: PlacementID,
        resolvedPlacementID: PlacementID,
        paywallVariationID: PaywallVariationID?,
        kind: Kind,
        startedAt: Date,
        lastCheckedAt: Date?,
        stage: Stage,
        diagnosticCode: String?,
        isPendingLocally: Bool,
        reviewRequired: Bool
    ) {
        self.attemptID = attemptID
        self.productID = productID
        self.requestedPlacementID = requestedPlacementID
        self.resolvedPlacementID = resolvedPlacementID
        self.paywallVariationID = paywallVariationID
        self.kind = kind
        self.startedAt = startedAt
        self.lastCheckedAt = lastCheckedAt
        self.stage = stage
        self.diagnosticCode = diagnosticCode
        self.isPendingLocally = isPendingLocally
        self.reviewRequired = reviewRequired
    }

    /// Plain text for a host application's support form or email. Contains no
    /// receipt, signed transaction, balance, account ID or payment details.
    public var supportText: String {
        let date = ISO8601DateFormatter()
        var lines = [
            "Purchase attempt: \(Self.supportSafe(attemptID.rawValue))",
            "Product: \(Self.supportSafe(productID.rawValue))",
            "Requested placement: \(Self.supportSafe(requestedPlacementID.rawValue))",
            "Resolved placement: \(Self.supportSafe(resolvedPlacementID.rawValue))",
            "Kind: \(kind.rawValue)",
            "Started: \(date.string(from: startedAt))",
            "Last stage: \(stage.rawValue)",
            "Local pending record: \(isPendingLocally ? "yes" : (stage == .localStoreUnavailable ? "unavailable" : "missing"))",
            "Needs review: \(reviewRequired ? "yes" : "no")"
        ]
        if let lastCheckedAt {
            lines.append("Last checked: \(date.string(from: lastCheckedAt))")
        }
        if let paywallVariationID {
            lines.append("Paywall variation: \(Self.supportSafe(paywallVariationID.rawValue))")
        }
        if let diagnosticCode {
            lines.append("Diagnostic code: \(Self.supportSafe(diagnosticCode))")
        }
        return lines.joined(separator: "\n")
    }

    private static func supportSafe(_ value: String) -> String {
        value.unicodeScalars.prefix(128).map { scalar in
            (32 ... 126).contains(scalar.value) ? String(scalar) : "_"
        }.joined()
    }
}
