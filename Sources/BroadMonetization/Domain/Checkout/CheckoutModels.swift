import BroadCore
import Foundation

public enum CheckoutMethod: String, Codable, CaseIterable, Equatable, Sendable {
    case apple
    case sbp
    case card
}

public struct CheckoutMethodsResolution: Equatable, Sendable {
    public let methods: [CheckoutMethod]
    public let storefront: Storefront?

    public init(
        methods: [CheckoutMethod],
        storefront: Storefront?
    ) {
        precondition(
            Set(methods).count == methods.count,
            "Available checkout methods must not contain duplicates"
        )

        self.methods = methods
        self.storefront = storefront
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

    public init(
        productID: ProductID,
        checkoutMethod: CheckoutMethod,
        confirmedAt: Date
    ) {
        self.productID = productID
        self.checkoutMethod = checkoutMethod
        self.confirmedAt = confirmedAt
    }
}

/// Raw result produced by the StoreKit/Adapty purchase adapter. A completed SDK
/// operation is not yet proof that premium access is active.
public enum PurchaseFailureDisposition: Equatable, Sendable {
    /// The provider purchase sheet was not started, or StoreKit definitively
    /// reported user cancellation. Clearing the durable intent is safe.
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
/// An RU payment page that merely opened resolves as `.pending`; only an
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
