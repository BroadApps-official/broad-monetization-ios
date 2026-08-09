import Foundation
import StoreKit

public protocol StoreKitEntitlementsClientProtocol: Sendable {
    func currentEntitlements(
        for productIDs: Set<String>
    ) async -> [StoreKitCurrentEntitlementRecord]
}

public enum StoreKitTransactionProductKind: Equatable, Sendable {
    case autoRenewable
    case nonConsumable
    case nonRenewable
    case consumable
    case unknown
}

public enum StoreKitCurrentEntitlementRecord: Equatable, Sendable {
    public struct Verified: Equatable, Sendable {
        public let productID: String
        public let appBundleID: String
        public let productKind: StoreKitTransactionProductKind
        public let purchaseDate: Date
        public let expirationDate: Date?
        public let revocationDate: Date?
        public let isUpgraded: Bool
        public let appAccountToken: UUID?

        public init(
            productID: String,
            appBundleID: String,
            productKind: StoreKitTransactionProductKind,
            purchaseDate: Date,
            expirationDate: Date?,
            revocationDate: Date?,
            isUpgraded: Bool,
            appAccountToken: UUID?
        ) {
            self.productID = productID
            self.appBundleID = appBundleID
            self.productKind = productKind
            self.purchaseDate = purchaseDate
            self.expirationDate = expirationDate
            self.revocationDate = revocationDate
            self.isUpgraded = isUpgraded
            self.appAccountToken = appAccountToken
        }
    }

    case verified(Verified)
    case unverified
}

public struct StoreKitCurrentEntitlementsClient: StoreKitEntitlementsClientProtocol {
    public init() {}

    public func currentEntitlements(
        for productIDs: Set<String>
    ) async -> [StoreKitCurrentEntitlementRecord] {
        #if compiler(>=6.1)
            if #available(iOS 18.4, *) {
                return await currentEntitlementsByProduct(productIDs)
            }
        #endif

        return await legacyCurrentEntitlements()
    }
}

private extension StoreKitCurrentEntitlementsClient {
    #if compiler(>=6.1)
        @available(iOS 18.4, *)
        func currentEntitlementsByProduct(
            _ productIDs: Set<String>
        ) async -> [StoreKitCurrentEntitlementRecord] {
            var records: [StoreKitCurrentEntitlementRecord] = []

            for productID in productIDs.sorted() {
                guard !Task.isCancelled else {
                    return records
                }

                for await result in Transaction.currentEntitlements(for: productID) {
                    guard !Task.isCancelled else {
                        return records
                    }
                    records.append(map(result))
                }
            }

            return records
        }
    #endif

    #if compiler(>=6.1)
        @available(iOS, introduced: 17.0, obsoleted: 18.4)
    #endif
    func legacyCurrentEntitlements() async -> [StoreKitCurrentEntitlementRecord] {
        var records: [StoreKitCurrentEntitlementRecord] = []

        for await result in Transaction.currentEntitlements {
            guard !Task.isCancelled else {
                return records
            }
            records.append(map(result))
        }

        return records
    }

    func map(
        _ result: VerificationResult<Transaction>
    ) -> StoreKitCurrentEntitlementRecord {
        switch result {
        case let .verified(transaction):
            .verified(
                StoreKitCurrentEntitlementRecord.Verified(
                    productID: transaction.productID,
                    appBundleID: transaction.appBundleID,
                    productKind: productKind(transaction.productType),
                    purchaseDate: transaction.purchaseDate,
                    expirationDate: transaction.expirationDate,
                    revocationDate: transaction.revocationDate,
                    isUpgraded: transaction.isUpgraded,
                    appAccountToken: transaction.appAccountToken
                )
            )
        case .unverified:
            .unverified
        }
    }

    func productKind(
        _ productType: Product.ProductType
    ) -> StoreKitTransactionProductKind {
        if productType == .autoRenewable {
            return .autoRenewable
        }
        if productType == .nonConsumable {
            return .nonConsumable
        }
        if productType == .nonRenewable {
            return .nonRenewable
        }
        if productType == .consumable {
            return .consumable
        }
        return .unknown
    }
}
