#!/usr/bin/env bash
set -euo pipefail

module_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT
core_root="$module_root/.build/checkouts/broad-core-ios/Sources/BroadCore"
source_root="$module_root/Sources/BroadMonetization"
core_sources=()
while IFS= read -r source; do core_sources+=("$source"); done < <(rg --files "$core_root/Domain" -g '*.swift')
xcrun swiftc -emit-library -emit-module -module-name BroadCore \
    "${core_sources[@]}" "$core_root/Infrastructure/Networking/NetworkFailureClassifier.swift" \
    "$core_root/Application/Storage/KeyValueStoreProtocol.swift" \
    -emit-module-path "$temporary_directory/BroadCore.swiftmodule" -o "$temporary_directory/libBroadCore.dylib"
sources=()
while IFS= read -r source; do sources+=("$source"); done < <(
    rg --files "$source_root/Domain" -g '*.swift' -g '!MonetizationUseCaseProtocols.swift'
)
xcrun swiftc -parse-as-library -strict-concurrency=complete -warnings-as-errors \
    -I "$temporary_directory" -L "$temporary_directory" -lBroadCore \
    -Xlinker -rpath -Xlinker "$temporary_directory" \
    "${sources[@]}" "$source_root/Data/SpecialOffers/PersistedSpecialOfferStateRepository.swift" \
    "$module_root/Scripts/ContractProbes/SpecialOfferMigrationProbe.swift" \
    -o "$temporary_directory/special-offer-migration-probe"
"$temporary_directory/special-offer-migration-probe"
