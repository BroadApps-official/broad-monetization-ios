#if DEBUG
    import BroadCore
    import Foundation
    import StoreKit

    /// Debug-only purchase repository that completes a purchase through the local
    /// `.storekit` StoreKit configuration attached to the run scheme, instead of a
    /// production provider.
    ///
    /// The paywall still shows and the catalog still comes from the real provider;
    /// only the payment is local, so a debug build can complete a purchase without
    /// real money and without provider receipt validation. Access is **not** granted
    /// here: the purchase produces a genuine StoreKit transaction, and premium is
    /// confirmed the usual way, by the entitlement engine matching that transaction
    /// against the premium catalog. This is the production-identical debug path, not
    /// a bypass. Not compiled into Release builds.
    public struct LocalStoreKitPurchaseRepository: PurchaseRepositoryProtocol {
        public init() {}

        public func purchase(
            _ request: PurchaseRequest
        ) async -> PurchaseAttemptOutcome {
            guard request.checkoutMethod == .apple else {
                return .failed(
                    Self.error(
                        "Only Apple checkout runs in the local StoreKit debug repository.",
                        code: "non-apple-checkout"
                    ),
                    disposition: .definitivelyNotPurchased
                )
            }

            let storeProduct: StoreKit.Product
            switch await localProduct(for: request.selection.product.productID) {
            case let .found(product):
                storeProduct = product
            case let .failed(outcome):
                return outcome
            }

            do {
                switch try await storeProduct.purchase() {
                case let .success(verification):
                    return await confirm(verification, for: request)
                case .userCancelled:
                    return .cancelled
                case .pending:
                    return .pending
                @unknown default:
                    // An outcome the adapter cannot read is not a failure: the
                    // durable intent must survive until a transaction proves otherwise.
                    return .pending
                }
            } catch {
                return .failed(
                    Self.error(
                        "The local purchase did not finish.",
                        code: "local-purchase-failed"
                    ),
                    disposition: .outcomeUnknown
                )
            }
        }

        /// Looks the product up in the local `.storekit` configuration. The lookup
        /// never charges, so a failure can drop the intent safely.
        private func localProduct(
            for productID: ProductID
        ) async -> LocalProductLookup {
            do {
                guard let found = try await StoreKit.Product.products(
                    for: [productID.rawValue]
                ).first else {
                    return .failed(.failed(
                        Self.error(
                            "\(productID.rawValue) is missing from the local .storekit configuration.",
                            code: "product-not-in-local-store"
                        ),
                        disposition: .definitivelyNotPurchased
                    ))
                }
                return .found(found)
            } catch {
                return .failed(.failed(
                    Self.error(
                        "The local StoreKit store could not be read.",
                        code: "local-store-unreadable"
                    ),
                    disposition: .definitivelyNotPurchased
                ))
            }
        }

        private enum LocalProductLookup {
            case found(StoreKit.Product)
            case failed(PurchaseAttemptOutcome)
        }

        private func confirm(
            _ verification: VerificationResult<StoreKit.Transaction>,
            for request: PurchaseRequest
        ) async -> PurchaseAttemptOutcome {
            switch verification {
            case let .verified(transaction):
                await transaction.finish()
                return .completed(
                    PurchaseConfirmation(
                        productID: request.selection.product.productID,
                        checkoutMethod: request.checkoutMethod,
                        confirmedAt: Date()
                    )
                )
            case .unverified:
                // Something was bought, but its signature does not check out. The
                // intent stays open for reconciliation.
                return .failed(
                    Self.error(
                        "The local purchase could not be verified.",
                        code: "local-purchase-unverified"
                    ),
                    disposition: .outcomeUnknown
                )
            }
        }

        private static func error(_ message: String, code: String) -> AppError {
            AppError(
                kind: .unavailable,
                userMessage: message,
                diagnosticCode: "debug.local-storekit.\(code)",
                isRetryable: false
            )
        }
    }

    /// Debug-only restore against the local StoreKit store. `AppStore.sync()`
    /// re-reads the local transactions; the entitlement engine decides what they
    /// mean. Not compiled into Release builds.
    public struct LocalStoreKitRestoreRepository: RestoreRepositoryProtocol {
        public init() {}

        public func restorePurchases() async -> RestoreAttemptOutcome {
            do {
                try await AppStore.sync()
                return .completed
            } catch {
                return .failed(
                    AppError(
                        kind: .unavailable,
                        userMessage: "The local StoreKit store could not be synchronised.",
                        diagnosticCode: "debug.local-storekit.restore-failed",
                        isRetryable: true
                    )
                )
            }
        }
    }
#endif
