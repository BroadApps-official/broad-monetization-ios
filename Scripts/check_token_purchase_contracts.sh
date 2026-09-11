#!/usr/bin/env bash
set -euo pipefail

module_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
probe_directory="$(mktemp -d)"
trap 'rm -rf "$probe_directory"' EXIT
core_root="$module_root/.build/checkouts/broad-core-ios/Sources/BroadCore"
source_root="$module_root/Sources/BroadMonetization"

core_sources=()
while IFS= read -r source; do core_sources+=("$source"); done < <(rg --files "$core_root/Domain" -g '*.swift')
xcrun swiftc -emit-library -emit-module -module-name BroadCore \
    "${core_sources[@]}" "$core_root/Infrastructure/Networking/NetworkFailureClassifier.swift" \
    -emit-module-path "$probe_directory/BroadCore.swiftmodule" -o "$probe_directory/libBroadCore.dylib"

# The token manager uses these production models and protocols directly.
# Unrelated aggregate use-case protocols pull in the RU HTTP application layer.
sources=()
while IFS= read -r source; do sources+=("$source"); done < <(
    rg --files "$source_root/Domain" -g '*.swift' -g '!MonetizationUseCaseProtocols.swift'
)
for source in \
    Application/Purchase/MonetizationOperationGate.swift \
    Application/PurchaseManagers/TokenPurchaseModels.swift \
    Application/PurchaseManagers/TokenPurchaseManager.swift \
    Data/Purchase/PendingTokenPurchaseStore.swift \
    Infrastructure/Analytics/NoOpMonetizationAnalytics.swift \
    Infrastructure/Analytics/NonBlockingMonetizationAnalytics.swift; do
    sources+=("$source_root/$source")
done
xcrun swiftc -parse-as-library -strict-concurrency=complete -warnings-as-errors \
    -I "$probe_directory" -L "$probe_directory" -lBroadCore \
    -Xlinker -rpath -Xlinker "$probe_directory" \
    "${sources[@]}" "$module_root/Scripts/ContractProbes/TokenPurchaseProbe.swift" \
    -o "$probe_directory/token-purchase-probe"
"$probe_directory/token-purchase-probe"
