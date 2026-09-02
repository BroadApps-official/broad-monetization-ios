#!/usr/bin/env bash

set -euo pipefail

module_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT

xcrun swiftc \
    "$module_root/Sources/BroadMonetization/Domain/Identifiers/MonetizationIdentifiers.swift" \
    "$module_root/Sources/BroadMonetization/Domain/Products/Money.swift" \
    "$module_root/Sources/BroadMonetization/Domain/Products/SubscriptionPeriod.swift" \
    "$module_root/Sources/BroadMonetization/Domain/Products/MonetizationProduct.swift" \
    "$module_root/Sources/BroadMonetization/Domain/Products/ProductPricePresentation.swift" \
    "$module_root/Scripts/ContractProbes/ProductPricePresentationProbe.swift" \
    -o "$temporary_directory/product-price-presentation-probe"

"$temporary_directory/product-price-presentation-probe"
