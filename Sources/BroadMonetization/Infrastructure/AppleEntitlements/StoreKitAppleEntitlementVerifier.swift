import BroadCore
import Foundation

public enum StoreKitEntitlementOwnershipPolicy: Equatable, Sendable {
    /// Premium follows the signed-in App Store account and is not bound to a host-app user.
    case appStoreAccount

    /// Premium is accepted only for this exact app account token.
    /// A relevant legacy transaction without a token is unresolved, never inactive.
    case appAccountToken(UUID)
}

public struct StoreKitAppleEntitlementConfiguration: Sendable {
    public let subject: EntitlementSubject
    public let appBundleIdentifier: String
    public let productCatalog: ApplePremiumProductCatalog
    public let ownershipPolicy: StoreKitEntitlementOwnershipPolicy

    public init(
        subject: EntitlementSubject,
        appBundleIdentifier: String,
        productCatalog: ApplePremiumProductCatalog,
        ownershipPolicy: StoreKitEntitlementOwnershipPolicy
    ) {
        let trimmedBundleIdentifier = appBundleIdentifier.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        precondition(
            !trimmedBundleIdentifier.isEmpty && trimmedBundleIdentifier == appBundleIdentifier,
            "App bundle identifier must be nonempty and contain no surrounding whitespace"
        )

        self.subject = subject
        self.appBundleIdentifier = appBundleIdentifier
        self.productCatalog = productCatalog
        self.ownershipPolicy = ownershipPolicy

        if case .appAccountToken = ownershipPolicy {
            precondition(
                !productCatalog.entries.contains { entry in
                    if case .nonRenewing = entry.kind {
                        return true
                    }
                    return false
                },
                "Token-bound non-renewing products require a transaction history adapter"
            )
        }
    }
}

public struct StoreKitAppleEntitlementVerifier: AppleEntitlementVerifierProtocol {
    private let configuration: StoreKitAppleEntitlementConfiguration
    private let client: any StoreKitEntitlementsClientProtocol
    private let clock: CacheClock

    public init(
        configuration: StoreKitAppleEntitlementConfiguration,
        client: any StoreKitEntitlementsClientProtocol = StoreKitCurrentEntitlementsClient(),
        clock: CacheClock = .system
    ) {
        self.configuration = configuration
        self.client = client
        self.clock = clock
    }

    public func verifyEntitlement(
        for subject: EntitlementSubject
    ) async -> EntitlementSourceResolution {
        guard subject == configuration.subject, !Task.isCancelled else {
            return .unresolved
        }

        let productIDs = Set(configuration.productCatalog.entries.map(\.productID))
        let records = await client.currentEntitlements(for: productIDs)

        guard !Task.isCancelled else {
            return .unresolved
        }

        return resolve(records, now: clock.now())
    }
}

private extension StoreKitAppleEntitlementVerifier {
    func resolve(
        _ records: [StoreKitCurrentEntitlementRecord],
        now: Date
    ) -> EntitlementSourceResolution {
        let resolutions = records.map { recordResolution($0, now: now) }
        let activeValidities: [EntitlementActiveValidity] = resolutions.compactMap {
            guard case let .active(validity) = $0 else {
                return nil
            }
            return validity
        }

        guard !activeValidities.isEmpty else {
            return resolutions.contains(.unresolved) ? .unresolved : .inactive
        }

        return .active(aggregate(activeValidities))
    }

    func recordResolution(
        _ record: StoreKitCurrentEntitlementRecord,
        now: Date
    ) -> EntitlementSourceResolution {
        switch record {
        case .unverified:
            .unresolved
        case let .verified(transaction):
            verifiedResolution(transaction, now: now)
        }
    }

    func verifiedResolution(
        _ transaction: StoreKitCurrentEntitlementRecord.Verified,
        now: Date
    ) -> EntitlementSourceResolution {
        guard
            let catalogEntry = configuration.productCatalog.entry(
                for: transaction.productID
            )
        else {
            return .inactive
        }

        switch ownershipEvaluation(transaction) {
        case .matches:
            break
        case .belongsToAnotherAppUser:
            return .inactive
        case .unresolved:
            return .unresolved
        }

        guard
            transaction.appBundleID == configuration.appBundleIdentifier,
            transactionMatchesCatalog(transaction, entry: catalogEntry)
        else {
            return .unresolved
        }
        guard transaction.revocationDate == nil else {
            return .inactive
        }
        guard !transaction.isUpgraded else {
            return .unresolved
        }

        return activeValidity(
            for: transaction,
            catalogEntry: catalogEntry,
            now: now
        )
    }

    func transactionMatchesCatalog(
        _ transaction: StoreKitCurrentEntitlementRecord.Verified,
        entry: ApplePremiumProductCatalog.Entry
    ) -> Bool {
        switch entry.kind {
        case .autoRenewable:
            transaction.productKind == .autoRenewable
        case .nonConsumable:
            transaction.productKind == .nonConsumable
        case .nonRenewing:
            transaction.productKind == .nonRenewable
        }
    }

    func ownershipEvaluation(
        _ transaction: StoreKitCurrentEntitlementRecord.Verified
    ) -> OwnershipEvaluation {
        switch configuration.ownershipPolicy {
        case .appStoreAccount:
            return .matches
        case let .appAccountToken(expectedToken):
            guard let transactionToken = transaction.appAccountToken else {
                return .unresolved
            }
            return transactionToken == expectedToken
                ? .matches
                : .belongsToAnotherAppUser
        }
    }

    func activeValidity(
        for transaction: StoreKitCurrentEntitlementRecord.Verified,
        catalogEntry: ApplePremiumProductCatalog.Entry,
        now: Date
    ) -> EntitlementSourceResolution {
        switch catalogEntry.kind {
        case .nonConsumable:
            return .active(.lifetime)
        case .autoRenewable:
            guard let expirationDate = transaction.expirationDate else {
                return .unresolved
            }
            guard expirationDate.timeIntervalSinceReferenceDate.isFinite else {
                return .unresolved
            }

            // currentEntitlements may retain a verified subscription during billing grace.
            return expirationDate > now
                ? .active(.expires(at: expirationDate))
                : .active(.unspecified)
        case let .nonRenewing(validFor):
            guard
                transaction.purchaseDate.timeIntervalSinceReferenceDate.isFinite,
                let expirationDate = adding(validFor, to: transaction.purchaseDate)
            else {
                return .unresolved
            }

            return now < expirationDate
                ? .active(.expires(at: expirationDate))
                : .inactive
        }
    }

    func aggregate(
        _ validities: [EntitlementActiveValidity]
    ) -> EntitlementActiveValidity {
        if validities.contains(.lifetime) {
            return .lifetime
        }
        if validities.contains(.unspecified) {
            return .unspecified
        }

        return validities.compactMap(\.expirationDate).max().map {
            .expires(at: $0)
        } ?? .unspecified
    }

    func adding(
        _ interval: TimeInterval,
        to date: Date
    ) -> Date? {
        let result = date.addingTimeInterval(interval)
        return result.timeIntervalSinceReferenceDate.isFinite ? result : nil
    }
}

private extension StoreKitAppleEntitlementVerifier {
    enum OwnershipEvaluation {
        case matches
        case belongsToAnotherAppUser
        case unresolved
    }
}
