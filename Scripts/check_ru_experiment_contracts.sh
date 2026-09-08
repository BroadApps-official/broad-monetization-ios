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
    -emit-module-path "$temporary_directory/BroadCore.swiftmodule" \
    -o "$temporary_directory/libBroadCore.dylib"

sources=()
while IFS= read -r source; do sources+=("$source"); done < <(rg --files "$source_root/Domain" -g '*.swift' -g '!MonetizationUseCaseProtocols.swift' -g '!RefreshEntitlementUseCaseProtocol.swift')
for directory in Infrastructure/RemoteConfig; do
    while IFS= read -r source; do sources+=("$source"); done < <(rg --files "$source_root/$directory" -g '*.swift')
done
for source in \
    Application/RUBilling/RUBillingGate.swift \
    Application/RUBilling/RUBillingDebugOverride.swift \
    Application/RUBilling/RUBillingExperimentTracker.swift \
    Application/RUBilling/RUExperimentCatalogSelector.swift \
    Data/Paywalls/LastValidRemoteConfigurationStore.swift \
    Infrastructure/RUBilling/SystemRUBillingDeviceContextProvider.swift \
    Infrastructure/RUBilling/RUBillingHTTPConfiguration.swift \
    Infrastructure/RUBilling/RUBillingAuthenticatedHTTPClient.swift \
    Infrastructure/RUBilling/RUExperimentHTTPConfiguration.swift \
    Infrastructure/RUBilling/URLSessionRUExperimentRepository.swift \
    Infrastructure/RUBilling/FlatRUCatalogResponseDecoder.swift \
    Infrastructure/RUBilling/RUBPriceFormatter.swift \
    Infrastructure/RUBilling/RUCatalogWireContract.swift \
    Infrastructure/RUBilling/BroadAppsRUCatalogWireDTO.swift \
    Infrastructure/RUBilling/BroadAppsRUBillingWireDTO.swift \
    Infrastructure/RUBilling/RUBillingSafeErrors.swift \
    Infrastructure/RUBilling/RUBillingWireContracts.swift; do
    sources+=("$source_root/$source")
done
while IFS= read -r source; do sources+=("$source"); done < <(rg --files "$module_root/Scripts/ContractProbes" -g 'RUExperiment*swift')
xcrun swiftc -parse-as-library -strict-concurrency=complete -warnings-as-errors \
    -I "$temporary_directory" -L "$temporary_directory" -lBroadCore \
    -Xlinker -rpath -Xlinker "$temporary_directory" \
    "${sources[@]}" -o "$temporary_directory/ru-experiment-probe"
"$temporary_directory/ru-experiment-probe"
