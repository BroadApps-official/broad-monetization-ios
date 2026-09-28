import Adapty
import BroadCore
import Foundation
#if DEBUG
    // swiftlint:disable oslog_outside_adapter
    import os

    // swiftlint:enable oslog_outside_adapter

    extension AdaptyPaywallRepository {
        static func logMissingProducts(
            in paywall: AdaptyPaywall,
            returned products: [any AdaptyPaywallProduct],
            placementID: PlacementID
        ) {
            var remaining = [String: Int]()
            for product in products {
                remaining[product.vendorProductId, default: 0] += 1
            }
            let expected = paywall.vendorProductIds
            var missing = [String]()
            for productID in expected {
                if let count = remaining[productID], count > 0 {
                    remaining[productID] = count - 1
                } else {
                    missing.append(productID)
                }
            }
            guard !missing.isEmpty else { return }
            let matched = expected.count - missing.count
            let details = "Placement \(placementID.rawValue): \(matched)/\(expected.count) products returned; "
                + "missing vendor product IDs: \(missing.joined(separator: ", ")). "
                + "Add them to the Debug .storekit file with App Store prices."
            let logger = Logger(subsystem: "BroadMonetization", category: "PaywallProducts")
            logger.warning("\(details, privacy: .public)")
        }
    }
#endif
