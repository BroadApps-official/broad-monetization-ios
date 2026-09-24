import BroadCore
import Foundation

public struct CheckoutMethod: RawRepresentable, Codable, Hashable, Sendable, ValidatedMonetizationIdentifier {
    public let rawValue: String
    public init(rawValue: String) {
        precondition(MonetizationIdentifierPolicy.isValid(rawValue))
        self.rawValue = rawValue
    }

    public static let apple = Self(rawValue: "apple")
}

/// Provider metadata is interpreted only by the explicitly installed provider.
public struct CheckoutMethodsResolution: Equatable, Sendable {
    public let methods: [CheckoutMethod]
    public let storefront: Storefront?
    public let providerID: String?
    public let providerData: Data?
    public init(methods: [CheckoutMethod], storefront: Storefront?, providerData: Data? = nil, providerID: String? = nil) {
        precondition(Set(methods).count == methods.count)
        self.methods = methods
        self.storefront = storefront
        self.providerID = providerID
        self.providerData = providerData
    }
}

public struct CheckoutOptions: Codable, Equatable, Sendable {
    public static let standard = CheckoutOptions()
    public let providerID: String?
    public let providerData: Data?
    public init(providerID: String? = nil, providerData: Data? = nil) {
        self.providerID = providerID
        self.providerData = providerData
    }
}

public struct ProductSelection: Codable, Equatable, Sendable {
    public let paywallPresentationID: PaywallPresentationID
    public let paywallReference: PaywallReference
    public let paywallVariationID: PaywallVariationID?
    public let requestedPlacementID: PlacementID
    public let resolvedPlacementID: PlacementID
    /// Exact provider-array position of the selected occurrence. It lets a provider
    /// safely rehydrate an evicted raw handle without collapsing duplicate SKUs.
    public let productIndex: Int
    public let product: MonetizationProduct

    public init(
        paywall: PaywallPayload,
        product: MonetizationProduct
    ) {
        guard let productIndex = paywall.products.firstIndex(where: { candidate in
            candidate.presentationID == product.presentationID
        }) else {
            preconditionFailure(
                "Selected product must belong to the supplied paywall presentation"
            )
        }

        paywallPresentationID = paywall.presentationID
        paywallReference = paywall.paywallReference
        paywallVariationID = paywall.variationID
        requestedPlacementID = paywall.origin.requestedPlacementID
        resolvedPlacementID = paywall.origin.resolvedPlacementID
        self.productIndex = productIndex
        self.product = product
    }
}

public struct PurchaseRequest: Codable, Equatable, Sendable {
    public let selection: ProductSelection
    public let checkoutMethod: CheckoutMethod

    public init(
        selection: ProductSelection,
        checkoutMethod: CheckoutMethod
    ) {
        self.selection = selection
        self.checkoutMethod = checkoutMethod
    }
}

/// Confirms that the selected provider completed a verified purchase operation.
/// Premium access still comes only from a subsequent authoritative entitlement refresh.
public struct PurchaseConfirmation: Codable, Equatable, Sendable {
    public let productID: ProductID
    public let checkoutMethod: CheckoutMethod
    public let confirmedAt: Date
    private let transactionEvidencePayload: PurchaseConfirmationEvidencePayload

    public init(
        productID: ProductID,
        checkoutMethod: CheckoutMethod,
        confirmedAt: Date
    ) {
        self.productID = productID
        self.checkoutMethod = checkoutMethod
        self.confirmedAt = confirmedAt
        transactionEvidencePayload = PurchaseConfirmationEvidencePayload(nil)
    }

    init(
        productID: ProductID,
        checkoutMethod: CheckoutMethod,
        confirmedAt: Date,
        capturedStoreTransactionEvidence: CapturedStoreTransactionEvidence
    ) {
        self.productID = productID
        self.checkoutMethod = checkoutMethod
        self.confirmedAt = confirmedAt
        transactionEvidencePayload = PurchaseConfirmationEvidencePayload(
            capturedStoreTransactionEvidence
        )
    }

    func takeCapturedStoreTransactionEvidence() -> CapturedStoreTransactionEvidence? {
        transactionEvidencePayload.evidence
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        productID = try container.decode(ProductID.self, forKey: .productID)
        checkoutMethod = try container.decode(
            CheckoutMethod.self,
            forKey: .checkoutMethod
        )
        confirmedAt = try container.decode(Date.self, forKey: .confirmedAt)
        transactionEvidencePayload = PurchaseConfirmationEvidencePayload(nil)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(productID, forKey: .productID)
        try container.encode(checkoutMethod, forKey: .checkoutMethod)
        try container.encode(confirmedAt, forKey: .confirmedAt)
    }

    private enum CodingKeys: String, CodingKey {
        case productID
        case checkoutMethod
        case confirmedAt
    }
}

/// Keeps the synthesized public equality contract independent of an internal
/// process-local payload.
private struct PurchaseConfirmationEvidencePayload: Equatable, Sendable {
    let evidence: CapturedStoreTransactionEvidence?

    init(_ evidence: CapturedStoreTransactionEvidence?) {
        self.evidence = evidence
    }

    static func == (_: Self, _: Self) -> Bool {
        true
    }
}

/// Process-local handoff of a StoreKit-verified JWS. It is deliberately omitted
/// from the public confirmation's Codable and Equatable contracts. The token
/// manager durably saves the evidence before backend fulfillment.
struct CapturedStoreTransactionEvidence: Equatable, Sendable {
    let transactionID: String
    let productID: String
    let signedTransaction: String
    let purchasedAt: Date
    let appBundleIdentifier: String
    let appAccountToken: UUID?
    let isConsumable: Bool
    let isPurchase: Bool
    let revocationDate: Date?
    let isUpgraded: Bool
}

/// Raw result produced by the StoreKit/Adapty purchase adapter. A completed SDK
/// operation is not yet proof that premium access is active.
public enum PurchaseFailureDisposition: Equatable, Sendable {
    /// The provider did not start a purchase, or StoreKit definitively reported
    /// cancellation or terminal failure without a completed transaction.
    /// Clearing the durable intent is safe.
    case definitivelyNotPurchased

    /// The adapter cannot prove whether StoreKit charged/completed. The durable
    /// intent must remain and reconcile through verified transaction history.
    case outcomeUnknown
}

public enum PurchaseAttemptOutcome: Equatable, Sendable {
    case completed(PurchaseConfirmation)
    case cancelled
    case pending
    case failed(AppError, disposition: PurchaseFailureDisposition)
}

/// Result exposed by the purchase use case after an authoritative entitlement
/// refresh with `.startNewGeneration`.
public enum PurchaseOutcome: Equatable, Sendable {
    case activated(EntitlementSnapshot)
    /// Verified terminal purchase for a consumable. No premium entitlement is expected.
    case completed(PurchaseConfirmation)
    case completedButUnverified(PurchaseConfirmation)
    case cancelled
    case pending
    case failed(AppError)
}

/// Provider-neutral checkout result consumed by paywall presentation.
/// An external payment page that merely opened resolves as `.pending`; only an
/// authoritative entitlement refresh may produce `.activated`.
public enum CheckoutSelectedProductOutcome: Equatable, Sendable {
    case activated(EntitlementSnapshot)
    case completed(PurchaseConfirmation)
    case completedButUnverified(PurchaseConfirmation)
    case cancelled
    case pending
    case failed(AppError)
}

/// Raw restore adapter result. Entitlement aggregation belongs to the use case.
public enum RestoreAttemptOutcome: Equatable, Sendable {
    case completed
    case failed(AppError)
}

public enum RestoreOutcome: Equatable, Sendable {
    /// Returned only after the unified entitlement refresh confirms active access.
    case restored(EntitlementSnapshot)

    /// All configured authoritative sources completed and explicitly reported inactive.
    case nothingFound

    /// One or more required sources could not be checked, so absence is not proven.
    case unavailable(AppError)

    /// The restore operation itself failed before an authoritative result was possible.
    case failed(AppError)
}

public enum MonetizationActivationOutcome: Equatable, Sendable {
    case activated
    case unavailable(AppError)
}
