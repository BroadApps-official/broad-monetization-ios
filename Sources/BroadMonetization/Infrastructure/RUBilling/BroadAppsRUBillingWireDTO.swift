import Foundation

struct BroadAppsRUCheckoutRequestDTO: Encodable {
    let productID: String
    let paymentMethod: String
    let acceptsAutoRenewal: Bool
    let appID: String
    let appBundle: String
}

struct BroadAppsRUCheckoutResponseDTO: Decodable {
    let checkoutSessionID: String
    let paymentURL: String
    let expiresAt: Date?
}

struct BroadAppsRUPaymentStatusRequestDTO: Encodable {
    let checkoutSessionID: String
    let appID: String
    let appBundle: String
}

struct BroadAppsRUPaymentStatusResponseDTO: Decodable {
    let checkoutSessionID: String
    let status: RUPaymentStatus
}

struct BroadAppsRUCancellationRequestDTO: Encodable {
    let subscriptionID: String
    let appID: String
    let appBundle: String
}

enum BroadAppsRUCancellationStatusDTO: String, Decodable {
    case cancelled
    case alreadyInactive = "already_inactive"
    case failed
}

struct BroadAppsRUCancellationResponseDTO: Decodable {
    let status: BroadAppsRUCancellationStatusDTO
    let effectiveUntil: Date?
}

struct BroadAppsRUEntitlementResponseDTO: Decodable {
    let subscriptionActive: Bool
    let subscriptionExpiresAt: Date?
    let subscriptionLifetime: Bool?
}

enum BroadAppsRUBillingWireError: Error {
    case invalidIdentifier
    case invalidCheckout
    case mismatchedCheckout
    case invalidCancellation
    case invalidEntitlement
}
