import Foundation

public enum RUBillingRequestMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
}

public struct RUBillingWireRequest: Sendable {
    public let method: RUBillingRequestMethod
    public let queryItems: [URLQueryItem]
    public let body: Data?

    public init(
        method: RUBillingRequestMethod,
        queryItems: [URLQueryItem] = [],
        body: Data? = nil
    ) {
        self.method = method
        self.queryItems = queryItems
        self.body = body
    }
}

public protocol RUCatalogRequestEncoderProtocol: Sendable {
    func encodeCatalogRequest(
        applicationID: String,
        appBundleIdentifier: String
    ) throws -> RUBillingWireRequest
}

public protocol RUCheckoutRequestEncoderProtocol: Sendable {
    /// Custom implementations may add transient receipt data supplied by the host.
    /// The returned body is neither persisted nor logged by the platform.
    func encodeCheckoutRequest(
        _ request: RUCheckoutRequest,
        applicationID: String,
        appBundleIdentifier: String
    ) async throws -> RUBillingWireRequest
}

public protocol RUCheckoutResponseDecoderProtocol: Sendable {
    func decodeCheckoutSession(from data: Data) throws -> RUCheckoutSession
}

public protocol RUPaymentStatusRequestEncoderProtocol: Sendable {
    func encodePaymentStatusRequest(
        checkoutSessionID: CheckoutSessionID,
        applicationID: String,
        appBundleIdentifier: String
    ) throws -> RUBillingWireRequest
}

public protocol RUPaymentStatusResponseDecoderProtocol: Sendable {
    func decodePaymentStatus(
        from data: Data,
        expectedCheckoutSessionID: CheckoutSessionID,
        checkedAt: Date
    ) throws -> RUPaymentStatusSnapshot
}

public protocol RUCancellationRequestEncoderProtocol: Sendable {
    func encodeCancellationRequest(
        subscriptionID: RUSubscriptionID,
        applicationID: String,
        appBundleIdentifier: String
    ) throws -> RUBillingWireRequest
}

public protocol RUCancellationResponseDecoderProtocol: Sendable {
    func decodeCancellationOutcome(from data: Data) throws -> RUSubscriptionCancellationOutcome
}

public struct RUBillingEntitlementRecord: Equatable, Sendable {
    public let subject: EntitlementSubject
    public let isActive: Bool
    public let expiresAt: Date?
    public let isLifetime: Bool

    public init(
        subject: EntitlementSubject,
        isActive: Bool,
        expiresAt: Date?,
        isLifetime: Bool
    ) {
        self.subject = subject
        self.isActive = isActive
        self.expiresAt = expiresAt
        self.isLifetime = isLifetime
    }
}

public protocol RUEntitlementRequestEncoderProtocol: Sendable {
    func encodeEntitlementRequest(
        applicationID: String,
        appBundleIdentifier: String
    ) throws -> RUBillingWireRequest
}

public protocol RUEntitlementResponseDecoderProtocol: Sendable {
    func decodeEntitlement(
        from data: Data,
        subject: EntitlementSubject
    ) throws -> RUBillingEntitlementRecord
}

/// The platform-owned wire schema. Endpoint paths remain host configuration.
/// Applications using another backend contract replace only the relevant
/// encoder/decoder protocols.
public struct BroadAppsRUBillingWireContract:
    RUCatalogRequestEncoderProtocol,
    RUCheckoutRequestEncoderProtocol,
    RUCheckoutResponseDecoderProtocol,
    RUPaymentStatusRequestEncoderProtocol,
    RUPaymentStatusResponseDecoderProtocol,
    RUCancellationRequestEncoderProtocol,
    RUCancellationResponseDecoderProtocol,
    RUEntitlementRequestEncoderProtocol,
    RUEntitlementResponseDecoderProtocol {
    public init() {}

    public func encodeCatalogRequest(
        applicationID: String,
        appBundleIdentifier: String
    ) throws -> RUBillingWireRequest {
        RUBillingWireRequest(
            method: .get,
            queryItems: applicationQuery(
                applicationID: applicationID,
                appBundleIdentifier: appBundleIdentifier
            )
        )
    }

    public func encodeCheckoutRequest(
        _ request: RUCheckoutRequest,
        applicationID: String,
        appBundleIdentifier: String
    ) async throws -> RUBillingWireRequest {
        try RUBillingWireRequest(
            method: .post,
            body: Self.makeEncoder().encode(
                BroadAppsRUCheckoutRequestDTO(
                    productID: request.productID.rawValue,
                    paymentMethod: request.method.rawValue,
                    acceptsAutoRenewal: request.acceptsAutoRenewal,
                    appID: applicationID,
                    appBundle: appBundleIdentifier
                )
            )
        )
    }

    public func decodeCheckoutSession(from data: Data) throws -> RUCheckoutSession {
        let response = try Self.makeDecoder().decode(BroadAppsRUCheckoutResponseDTO.self, from: data)
        let sessionID = try Self.validatedIdentifier(response.checkoutSessionID)
        guard let paymentURL = URL(string: response.paymentURL),
              Self.isSafePaymentURL(paymentURL),
              response.expiresAt?.timeIntervalSinceReferenceDate.isFinite != false
        else {
            throw BroadAppsRUBillingWireError.invalidCheckout
        }

        return RUCheckoutSession(
            id: CheckoutSessionID(rawValue: sessionID),
            paymentURL: paymentURL,
            expiresAt: response.expiresAt
        )
    }

    public func encodePaymentStatusRequest(
        checkoutSessionID: CheckoutSessionID,
        applicationID: String,
        appBundleIdentifier: String
    ) throws -> RUBillingWireRequest {
        try RUBillingWireRequest(
            method: .post,
            body: Self.makeEncoder().encode(
                BroadAppsRUPaymentStatusRequestDTO(
                    checkoutSessionID: checkoutSessionID.rawValue,
                    appID: applicationID,
                    appBundle: appBundleIdentifier
                )
            )
        )
    }

    public func decodePaymentStatus(
        from data: Data,
        expectedCheckoutSessionID: CheckoutSessionID,
        checkedAt: Date
    ) throws -> RUPaymentStatusSnapshot {
        let response = try Self.makeDecoder().decode(BroadAppsRUPaymentStatusResponseDTO.self, from: data)
        guard response.checkoutSessionID == expectedCheckoutSessionID.rawValue,
              checkedAt.timeIntervalSinceReferenceDate.isFinite
        else {
            throw BroadAppsRUBillingWireError.mismatchedCheckout
        }
        return RUPaymentStatusSnapshot(
            checkoutSessionID: expectedCheckoutSessionID,
            status: response.status,
            checkedAt: checkedAt
        )
    }

    public func encodeCancellationRequest(
        subscriptionID: RUSubscriptionID,
        applicationID: String,
        appBundleIdentifier: String
    ) throws -> RUBillingWireRequest {
        try RUBillingWireRequest(
            method: .post,
            body: Self.makeEncoder().encode(
                BroadAppsRUCancellationRequestDTO(
                    subscriptionID: subscriptionID.rawValue,
                    appID: applicationID,
                    appBundle: appBundleIdentifier
                )
            )
        )
    }

    public func decodeCancellationOutcome(from data: Data) throws -> RUSubscriptionCancellationOutcome {
        let response = try Self.makeDecoder().decode(BroadAppsRUCancellationResponseDTO.self, from: data)
        guard response.effectiveUntil?.timeIntervalSinceReferenceDate.isFinite != false else {
            throw BroadAppsRUBillingWireError.invalidCancellation
        }

        switch response.status {
        case .cancelled:
            return .cancelled(effectiveUntil: response.effectiveUntil)
        case .alreadyInactive:
            return .alreadyInactive
        case .failed:
            return .failed(RUBillingSafeErrors.cancellationFailed)
        }
    }

    public func encodeEntitlementRequest(
        applicationID: String,
        appBundleIdentifier: String
    ) throws -> RUBillingWireRequest {
        RUBillingWireRequest(
            method: .get,
            queryItems: applicationQuery(
                applicationID: applicationID,
                appBundleIdentifier: appBundleIdentifier
            )
        )
    }

    public func decodeEntitlement(
        from data: Data,
        subject: EntitlementSubject
    ) throws -> RUBillingEntitlementRecord {
        let response = try Self.makeDecoder().decode(BroadAppsRUEntitlementResponseDTO.self, from: data)
        guard response.subscriptionExpiresAt?.timeIntervalSinceReferenceDate.isFinite != false else {
            throw BroadAppsRUBillingWireError.invalidEntitlement
        }
        return RUBillingEntitlementRecord(
            subject: subject,
            isActive: response.subscriptionActive,
            expiresAt: response.subscriptionExpiresAt,
            isLifetime: response.subscriptionLifetime ?? false
        )
    }
}

private extension BroadAppsRUBillingWireContract {
    func applicationQuery(
        applicationID: String,
        appBundleIdentifier: String
    ) -> [URLQueryItem] {
        [
            URLQueryItem(name: "app_id", value: applicationID),
            URLQueryItem(name: "app_bundle", value: appBundleIdentifier)
        ]
    }

    static func validatedIdentifier(_ value: String) throws -> String {
        guard MonetizationIdentifierPolicy.isValid(value) else {
            throw BroadAppsRUBillingWireError.invalidIdentifier
        }
        return value
    }

    static func isSafePaymentURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
            && url.host?.isEmpty == false
            && url.user == nil
            && url.password == nil
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard let date = RUBillingWireDateParser.date(from: value) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid RU billing date"
                )
            }
            return date
        }
        return decoder
    }
}

enum RUBillingWireDateParser {
    static func date(from value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
