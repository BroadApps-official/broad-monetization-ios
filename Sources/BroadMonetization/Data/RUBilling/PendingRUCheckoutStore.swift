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
        expiresAt: Date?
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
            expiresAt: value.expiresAt
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

public enum PendingRUCheckoutState: Equatable, Sendable {
    case none
    case pending(PendingRUCheckoutContext)
    /// An app-wide financial blocker exists for another identity. Its backend
    /// session and attempt identifiers are deliberately not disclosed.
    case blockedByAnotherSubject
    case unavailable
}

public protocol PendingRUCheckoutStoreProtocol: PendingOperationBlockerProtocol {
    func state() async -> PendingRUCheckoutState
    func save(_ context: PendingRUCheckoutContext) async -> Bool
    func clear(
        checkoutSessionID: CheckoutSessionID,
        attemptID: MonetizationAttemptID
    ) async -> Bool
}

public actor PendingRUCheckoutStore: PendingRUCheckoutStoreProtocol {
    public nonisolated let pendingOperationBlockerKey: PendingOperationBlockerKey

    private struct Record: Codable, Equatable, Sendable {
        let subjectKey: String
        let applicationIdentifier: String
        let context: PendingRUCheckoutContext

        init(
            subjectKey: String,
            applicationIdentifier: String,
            context: PendingRUCheckoutContext
        ) {
            precondition(
                MonetizationIdentifierPolicy.isValid(subjectKey)
                    && MonetizationIdentifierPolicy.isValid(applicationIdentifier),
                "Pending RU checkout scope must be valid"
            )
            self.subjectKey = subjectKey
            self.applicationIdentifier = applicationIdentifier
            self.context = context
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let subjectKey = try container.decode(String.self, forKey: .subjectKey)
            let applicationIdentifier = try container.decode(
                String.self,
                forKey: .applicationIdentifier
            )
            guard MonetizationIdentifierPolicy.isValid(subjectKey),
                  MonetizationIdentifierPolicy.isValid(applicationIdentifier)
            else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "Invalid persisted RU checkout scope"
                    )
                )
            }
            try self.init(
                subjectKey: subjectKey,
                applicationIdentifier: applicationIdentifier,
                context: container.decode(
                    PendingRUCheckoutContext.self,
                    forKey: .context
                )
            )
        }
    }

    private let cache: any CacheRepositoryProtocol
    private let key: CacheKey<Record>
    private let subjectKey: String
    private let applicationIdentifier: String
    private let authorizationBinding: SubjectAuthorizationBinding
    private let clock: CacheClock

    public init(
        subject: EntitlementSubject,
        applicationIdentifier: String,
        authorizationBinding: SubjectAuthorizationBinding,
        cache: any CacheRepositoryProtocol,
        retention: TimeInterval = 24 * 60 * 60,
        clock: CacheClock = .system
    ) {
        precondition(retention.isFinite && retention > 0, "Pending checkout retention must be finite and positive")
        precondition(
            MonetizationIdentifierPolicy.isValid(applicationIdentifier),
            "Application identifier must be valid"
        )
        precondition(
            authorizationBinding.subject == subject,
            "Pending RU checkout binding must match the exact subject"
        )
        self.cache = cache
        subjectKey = subject.cacheKeyComponent
        self.applicationIdentifier = applicationIdentifier
        self.authorizationBinding = authorizationBinding
        pendingOperationBlockerKey = PendingOperationBlockerKey(
            kind: .ruCheckout,
            applicationIdentifier: applicationIdentifier
        )
        key = CacheKey(
            // One app-wide key blocks a second Apple/RU charge across host
            // login/logout. The record retains the originating subject so a
            // different identity never polls its backend session.
            name: "pending-ru-checkout-\(applicationIdentifier)",
            schemaIdentifier: "dev.broadapps.monetization.pending-ru-checkout",
            version: 1,
            policy: CachePolicy(
                timeToLive: retention,
                corruptedEntryAction: .preserve,
                schemaMismatchAction: .preserve,
                versionMismatchAction: .preserve
            )
        )
        self.clock = clock
    }

    /// Storage failure is treated as potentially pending. Starting another
    /// payment is less safe than temporarily declining checkout/restore when a
    /// durable financial state cannot be inspected.
    public func hasPendingMonetizationOperation() async -> Bool {
        switch await state() {
        case .pending, .blockedByAnotherSubject, .unavailable:
            true
        case .none:
            false
        }
    }

    public func save(_ context: PendingRUCheckoutContext) async -> Bool {
        guard authorizationBinding.isCurrent(),
              context.expiresAt.map({ $0 > clock.now() }) ?? true
        else {
            return false
        }
        do {
            let inserted = try await cache.insertIfMissing(
                Record(
                    subjectKey: subjectKey,
                    applicationIdentifier: applicationIdentifier,
                    context: context
                ),
                for: key
            )
            return inserted && authorizationBinding.isCurrent()
        } catch {
            return false
        }
    }

    public func clear(
        checkoutSessionID: CheckoutSessionID,
        attemptID: MonetizationAttemptID
    ) async -> Bool {
        guard authorizationBinding.isCurrent() else {
            return false
        }
        let result: CacheReadResult<Record>
        do {
            result = try await cache.read(key)
        } catch {
            return false
        }
        let record: Record
        switch result {
        case let .fresh(envelope), let .stale(envelope):
            record = envelope.value
        case .missing:
            return false
        }
        guard record.applicationIdentifier == applicationIdentifier,
              record.subjectKey == subjectKey,
              authorizationBinding.isCurrent(),
              record.context.checkoutSessionID == checkoutSessionID,
              record.context.attemptID == attemptID
        else {
            return false
        }
        do {
            let removed = try await cache.remove(key, ifMatching: record)
            guard removed else {
                return false
            }
            guard authorizationBinding.isCurrent() else {
                // Identity changed while compare-and-remove was suspended. Put
                // the exact old blocker back unless another attempt already won.
                _ = try? await cache.insertIfMissing(record, for: key)
                return false
            }
            return true
        } catch {
            return false
        }
    }

    public func state() async -> PendingRUCheckoutState {
        guard authorizationBinding.isCurrent() else {
            return .unavailable
        }
        let result: CacheReadResult<Record>
        do {
            result = try await cache.read(key)
        } catch {
            return .unavailable
        }

        let record: Record
        switch result {
        case let .fresh(envelope), let .stale(envelope):
            record = envelope.value
        case .missing(.notFound):
            return .none
        case .missing:
            return .unavailable
        }
        guard authorizationBinding.isCurrent(),
              record.applicationIdentifier == applicationIdentifier
        else {
            return .unavailable
        }
        guard record.subjectKey == subjectKey else {
            return .blockedByAnotherSubject
        }

        // Neither cache TTL nor a server timestamp compared with mutable device
        // wall-clock time proves that a payment URL is no longer payable. Only
        // a terminal backend status may clear this blocker.
        return .pending(record.context)
    }
}
