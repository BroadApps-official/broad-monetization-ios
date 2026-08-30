import BroadCore
import Foundation

public enum RUCatalogProductKind: String, Codable, Equatable, Sendable {
    case subscription
    case tokens
    case coupon
    case unknown
}

public struct RUCatalogPayload: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case products
        case fetchedAt
    }

    /// Backend order and duplicate mappings are preserved intentionally.
    public let products: [RUCatalogProduct]
    public let fetchedAt: Date

    public init(
        products: [RUCatalogProduct],
        fetchedAt: Date
    ) {
        precondition(
            fetchedAt.timeIntervalSinceReferenceDate.isFinite,
            "RU catalog fetch date must be finite"
        )
        self.products = products
        self.fetchedAt = fetchedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let products = try container.decode(
            [RUCatalogProduct].self,
            forKey: .products
        )
        let fetchedAt = try container.decode(Date.self, forKey: .fetchedAt)
        guard fetchedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw RUBillingPersistedValueValidator.decodingError(
                codingPath: decoder.codingPath,
                description: "Invalid persisted RU catalog fetch date"
            )
        }

        self.init(products: products, fetchedAt: fetchedAt)
    }
}

public enum RUCatalogLoadOutcome: Equatable, Sendable {
    case loaded(RUCatalogPayload)
    case unavailable(AppError)
}

public struct RUCheckoutRequest: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case productID
        case method
        case acceptsAutoRenewal
        case customerEmail
    }

    public let productID: RUCatalogProductID
    public let method: CheckoutMethod
    public let acceptsAutoRenewal: Bool
    public let customerEmail: String?

    public init(
        productID: RUCatalogProductID,
        method: CheckoutMethod,
        acceptsAutoRenewal: Bool,
        customerEmail: String? = nil
    ) {
        precondition(method == .sbp || method == .card, "RU checkout supports only SBP or card")
        self.productID = productID
        self.method = method
        self.acceptsAutoRenewal = acceptsAutoRenewal
        let normalizedEmail = customerEmail?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        self.customerEmail = normalizedEmail?.isEmpty == false
            ? normalizedEmail
            : nil
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let productID = try container.decode(
            RUCatalogProductID.self,
            forKey: .productID
        )
        let method = try container.decode(CheckoutMethod.self, forKey: .method)
        let acceptsAutoRenewal = try container.decode(
            Bool.self,
            forKey: .acceptsAutoRenewal
        )
        let customerEmail = try container.decodeIfPresent(
            String.self,
            forKey: .customerEmail
        )

        guard MonetizationIdentifierPolicy.isValid(productID.rawValue),
              method == .sbp || method == .card
        else {
            throw RUBillingPersistedValueValidator.decodingError(
                codingPath: decoder.codingPath,
                description: "Invalid decoded RU checkout request"
            )
        }

        self.init(
            productID: RUCatalogProductID(rawValue: productID.rawValue),
            method: method,
            acceptsAutoRenewal: acceptsAutoRenewal,
            customerEmail: customerEmail
        )
    }
}

public struct RUCheckoutSession: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case id
        case paymentURL
        case expiresAt
    }

    public let id: CheckoutSessionID
    public let paymentURL: URL
    public let expiresAt: Date?

    public init(
        id: CheckoutSessionID,
        paymentURL: URL,
        expiresAt: Date? = nil
    ) {
        precondition(
            paymentURL.scheme?.lowercased() == "https",
            "RU checkout payment URL must use HTTPS"
        )
        precondition(
            expiresAt?.timeIntervalSinceReferenceDate.isFinite != false,
            "RU checkout expiration must be finite"
        )

        self.id = id
        self.paymentURL = paymentURL
        self.expiresAt = expiresAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(CheckoutSessionID.self, forKey: .id)
        let paymentURL = try container.decode(URL.self, forKey: .paymentURL)
        let expiresAt = try container.decodeIfPresent(Date.self, forKey: .expiresAt)

        guard MonetizationIdentifierPolicy.isValid(id.rawValue),
              paymentURL.scheme?.lowercased() == "https",
              expiresAt?.timeIntervalSinceReferenceDate.isFinite != false
        else {
            throw RUBillingPersistedValueValidator.decodingError(
                codingPath: decoder.codingPath,
                description: "Invalid decoded RU checkout session"
            )
        }

        self.init(
            id: CheckoutSessionID(rawValue: id.rawValue),
            paymentURL: paymentURL,
            expiresAt: expiresAt
        )
    }
}

enum RUCheckoutCreationOutcome: Sendable {
    case created(
        RUCheckoutSession,
        authorizationProof: SubjectAuthorizationProof
    )
    case unavailable(AppError)
    case failed(AppError)
}

public enum RUPaymentStatus: String, Codable, Equatable, Sendable {
    case pending
    case paid
    case failed
    case cancelled
    case expired
}

public struct RUPaymentStatusSnapshot: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case checkoutSessionID
        case status
        case checkedAt
    }

    public let checkoutSessionID: CheckoutSessionID
    public let status: RUPaymentStatus
    public let checkedAt: Date

    public init(
        checkoutSessionID: CheckoutSessionID,
        status: RUPaymentStatus,
        checkedAt: Date
    ) {
        precondition(
            checkedAt.timeIntervalSinceReferenceDate.isFinite,
            "RU payment status check date must be finite"
        )
        self.checkoutSessionID = checkoutSessionID
        self.status = status
        self.checkedAt = checkedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let checkoutSessionID = try container.decode(
            CheckoutSessionID.self,
            forKey: .checkoutSessionID
        )
        let status = try container.decode(
            RUPaymentStatus.self,
            forKey: .status
        )
        let checkedAt = try container.decode(Date.self, forKey: .checkedAt)

        guard MonetizationIdentifierPolicy.isValid(checkoutSessionID.rawValue),
              checkedAt.timeIntervalSinceReferenceDate.isFinite
        else {
            throw RUBillingPersistedValueValidator.decodingError(
                codingPath: decoder.codingPath,
                description: "Invalid decoded RU payment status"
            )
        }

        self.init(
            checkoutSessionID: CheckoutSessionID(
                rawValue: checkoutSessionID.rawValue
            ),
            status: status,
            checkedAt: checkedAt
        )
    }
}

public enum RUPaymentStatusOutcome: Equatable, Sendable {
    case resolved(RUPaymentStatusSnapshot)
    case unavailable(AppError)
}

public enum RUPaymentRefreshOutcome: Equatable, Sendable {
    case active(EntitlementSnapshot)
    case pending
    case inactive
    case unavailable(AppError)
}

private extension String? {
    var nonBlank: String? {
        guard let value = self else {
            return nil
        }

        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
    }
}

enum RUBillingPersistedValueValidator {
    static func isValid(_ money: Money?) -> Bool {
        guard let money else {
            return true
        }

        let normalizedCode = money.currencyCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        return !money.amount.isNaN
            && money.amount >= 0
            && normalizedCode.count == 3
            && normalizedCode.allSatisfy { $0.isASCII && $0.isLetter }
    }

    static func isValid(_ period: SubscriptionPeriod) -> Bool {
        if let count = period.count, count <= 0 {
            return false
        }

        switch period.unit {
        case .day, .week, .month, .year:
            return period.count != nil
        case let .custom(rawUnit):
            let trimmedUnit = rawUnit.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            return !trimmedUnit.isEmpty && trimmedUnit == rawUnit
        case .unknown:
            return true
        }
    }

    static func decodingError(
        codingPath: [any CodingKey],
        description: String
    ) -> DecodingError {
        DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: codingPath,
                debugDescription: description
            )
        )
    }
}
