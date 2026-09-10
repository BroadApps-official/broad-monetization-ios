import Foundation

/// CloudPayments checkout and effective-policy contracts used by current apps.
/// No payment-status request or backend checkout identifier is required.
public struct BroadAppsAccountPolicyWireContract:
    RUCheckoutRequestEncoderProtocol, RUCheckoutResponseDecoderProtocol,
    RUEntitlementRequestEncoderProtocol, RUEntitlementResponseDecoderProtocol {
    public init() {}

    public func encodeCheckoutRequest(
        _ request: RUCheckoutRequest,
        applicationID _: String,
        appBundleIdentifier _: String
    ) async throws -> RUBillingWireRequest {
        try RUBillingWireRequest(method: .post, body: JSONEncoder().encode(
            CheckoutBody(productId: request.productID.rawValue, customerEmail: request.customerEmail)
        ))
    }

    public func decodeCheckoutSession(from data: Data) throws -> RUCheckoutSession {
        let response = try Self.decoder().decode(CheckoutResponse.self, from: data)
        guard let url = URL(string: response.paymentUrl),
              url.scheme?.lowercased() == "https", url.host?.isEmpty == false,
              url.user == nil, url.password == nil else {
            throw BroadAppsRUBillingWireError.invalidCheckout
        }
        // Only correlates local pending state. Never sent as a backend payment ID.
        let expiresAt = try response.expiresAt.map { raw in
            guard let date = RUBillingWireDateParser.date(from: raw) else {
                throw BroadAppsRUBillingWireError.invalidCheckout
            }
            return date
        }
        return RUCheckoutSession(
            id: CheckoutSessionID(rawValue: UUID().uuidString), paymentURL: url, expiresAt: expiresAt
        )
    }

    public func encodeEntitlementRequest(
        applicationID _: String,
        appBundleIdentifier _: String
    ) throws -> RUBillingWireRequest {
        RUBillingWireRequest(method: .get)
    }

    public func decodeEntitlement(from data: Data, subject: EntitlementSubject) throws -> RUBillingEntitlementRecord {
        let response = try Self.decoder().decode(PolicyResponse.self, from: data)
        let expiration = try response.subscriptionExpiresAt.map { raw in
            guard let date = RUBillingWireDateParser.date(from: raw) else {
                throw BroadAppsRUBillingWireError.invalidEntitlement
            }
            return date
        }
        return RUBillingEntitlementRecord(
            subject: subject, isActive: response.isSubscribed, expiresAt: expiration,
            isLifetime: false, planName: response.plan, isAutoRenewalCancelled: response.willRenew == false
        )
    }

    public func decodePolicy(from data: Data, subject: EntitlementSubject) throws -> RUAccountPolicy {
        let response = try Self.decoder().decode(PolicyResponse.self, from: data)
        guard response.creditsBalance.map({ $0 >= 0 }) != false else {
            throw BroadAppsRUBillingWireError.invalidEntitlement
        }
        return RUAccountPolicy(
            subject: subject, isSubscribed: response.isSubscribed,
            plan: response.plan, creditsBalance: response.creditsBalance
        )
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}

private struct CheckoutBody: Encodable {
    let productId: String
    let customerEmail: String?
}

private struct CheckoutResponse: Decodable {
    let paymentUrl: String
    let expiresAt: String?
}

private struct PolicyResponse: Decodable {
    let isSubscribed: Bool
    let plan: String?
    let creditsBalance: Int?
    let subscriptionExpiresAt: String?
    let willRenew: Bool?
}
