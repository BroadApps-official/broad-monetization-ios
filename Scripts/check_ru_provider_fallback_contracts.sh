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
    "${core_sources[@]}" "$core_root/Infrastructure/Networking/NetworkFailureClassifier.swift" "$core_root/Infrastructure/Logging/NoOpBroadLogger.swift" \
    -emit-module-path "$temporary_directory/BroadCore.swiftmodule" \
    -o "$temporary_directory/libBroadCore.dylib"

sources=()
while IFS= read -r source; do sources+=("$source"); done < <(rg --files "$source_root/Domain" -g '*.swift')
for source in \
    Application/Paywalls/LoadPaywallUseCase.swift \
    Application/Paywalls/LoadPaywallWithRUFallbackUseCase.swift \
    Application/RUBilling/LoadRUSubscriptionManagementStatusUseCase.swift \
    Application/RUBilling/RUBillingGate.swift \
    Application/RUBilling/RUBillingDebugOverride.swift \
    Application/RUBilling/RUCatalogProductMatcher.swift \
    Application/RUBilling/RUExperimentCatalogSelector.swift \
    Application/RUBilling/ResolveCheckoutMethodsUseCase.swift \
    Infrastructure/Analytics/NoOpMonetizationAnalytics.swift \
    Infrastructure/Analytics/NonBlockingMonetizationAnalytics.swift \
    Infrastructure/RUBilling/SystemRUBillingDeviceContextProvider.swift \
    Infrastructure/RUBilling/URLSessionRUBillingEntitlementClient.swift \
    Infrastructure/RUBilling/RUBillingHTTPConfiguration.swift \
    Infrastructure/RUBilling/RUBillingAuthenticatedHTTPClient.swift \
    Infrastructure/RUBilling/RUBillingWireContracts.swift \
    Infrastructure/RUBilling/BroadAppsRUBillingWireDTO.swift \
    Infrastructure/RUBilling/RUBillingSafeErrors.swift; do
    sources+=("$source_root/$source")
done
while IFS= read -r source; do sources+=("$source"); done < <(rg --files "$source_root/Infrastructure/RemoteConfig" -g '*.swift')
sources+=("$module_root/Scripts/ContractProbes/RUProviderFallbackProbe.swift")
sources+=("$module_root/Scripts/ContractProbes/RUDefaultProductsProbe.swift")
xcrun swiftc -parse-as-library -strict-concurrency=complete -warnings-as-errors \
    -I "$temporary_directory" -L "$temporary_directory" -lBroadCore \
    -Xlinker -rpath -Xlinker "$temporary_directory" \
    "${sources[@]}" -o "$temporary_directory/ru-provider-fallback-probe"
"$temporary_directory/ru-provider-fallback-probe"
