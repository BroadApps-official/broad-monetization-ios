#!/usr/bin/env bash

set -euo pipefail

module_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
module_name="$(/usr/bin/ruby -rjson -e 'puts JSON.parse(File.read(ARGV.fetch(0))).fetch("module")' "$module_root/ModuleContract.json")"
sandbox_name="$(/usr/bin/ruby -rjson -e 'puts JSON.parse(File.read(ARGV.fetch(0))).fetch("sandbox")' "$module_root/ModuleContract.json")"
expected_swiftlint_version="0.62.2"
swiftlint_binary="$module_root/.build/tooling/swiftlint-$expected_swiftlint_version/swiftlint"
derived_data="$module_root/.build/DerivedData"
swift_module_cache="$module_root/.build/SwiftModuleCache"
swiftpm_cache="$module_root/.build/SwiftPMCache"
swiftpm_config="$module_root/.build/SwiftPMConfig"
swiftpm_security="$module_root/.build/SwiftPMSecurity"
ios_simulator_sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
simulator_arch="$(uname -m)"
translation_state="$(sysctl -in sysctl.proc_translated 2>/dev/null || true)"

if [[ "$simulator_arch" == "x86_64" && "$translation_state" == "1" ]]; then
    simulator_arch="arm64"
fi
if [[ "$simulator_arch" != "arm64" && "$simulator_arch" != "x86_64" ]]; then
    echo "Unsupported simulator architecture: $simulator_arch"
    exit 1
fi

mkdir -p "$swift_module_cache" "$swiftpm_cache" "$swiftpm_config" "$swiftpm_security"
export CLANG_MODULE_CACHE_PATH="$swift_module_cache"
export SWIFT_MODULECACHE_PATH="$swift_module_cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$swift_module_cache"

echo "[1/9] Structure, dependency boundaries and secret patterns"
bash "$module_root/Scripts/check_structure.sh"

echo "[2/9] Documentation links and contracts"
bash "$module_root/Scripts/check_documentation.sh"
bash "$module_root/Scripts/check_release_version.sh"

echo "[3/9] SwiftFormat"
bash "$module_root/Scripts/install_swiftformat.sh"
bash "$module_root/Scripts/install_build_tools.sh"
"$module_root/.build/tooling/swiftformat-0.62.1/swiftformat" \
    --lint \
    --config "$module_root/.swiftformat" \
    "$module_root/Sources" \
    "$module_root/Examples/$sandbox_name/Sources" \
    "$module_root/Scripts/ContractProbes"

echo "[4/9] SwiftLint"
actual_swiftlint_version="$("$swiftlint_binary" version | tr -d '[:space:]')"
if [[ "$actual_swiftlint_version" != "$expected_swiftlint_version" ]]; then
    echo "SwiftLint version mismatch: expected $expected_swiftlint_version, got $actual_swiftlint_version."
    exit 1
fi
"$swiftlint_binary" lint --strict --config "$module_root/.swiftlint.yml"

echo "[5/9] Swift Package, Debug iPhone Simulator"
swift build \
    --quiet \
    --package-path "$module_root" \
    --cache-path "$swiftpm_cache" \
    --config-path "$swiftpm_config" \
    --security-path "$swiftpm_security" \
    --configuration debug \
    --triple "${simulator_arch}-apple-ios17.0-simulator" \
    --sdk "$ios_simulator_sdk" \
    -Xswiftc -strict-concurrency=complete \
    -Xswiftc -warnings-as-errors

echo "[6/9] Executable contract probes and public API report"
bash "$module_root/Scripts/check_remote_feature_contracts.sh"
bash "$module_root/Scripts/check_adapty_experiment_contracts.sh"
bash "$module_root/Scripts/check_product_price_presentation_contract.sh"
bash "$module_root/Scripts/check_special_offer_campaign_contract.sh"
bash "$module_root/Scripts/generate_public_api_report.sh"

echo "[7/9] Standalone iPhone sandbox, Debug Simulator"
bash "$module_root/Scripts/generate_sandbox.sh"
xcodebuild \
    -quiet \
    -project "$module_root/Examples/$sandbox_name/$sandbox_name.xcodeproj" \
    -scheme "$sandbox_name" \
    -configuration Debug \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$derived_data" \
    CODE_SIGNING_ALLOWED=NO \
    build

echo "[8/9] Standalone iPhone sandbox, Release generic iOS (unsigned)"
xcodebuild \
    -quiet \
    -project "$module_root/Examples/$sandbox_name/$sandbox_name.xcodeproj" \
    -scheme "$sandbox_name" \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$derived_data" \
    CODE_SIGNING_ALLOWED=NO \
    build
echo "[9/9] DocC and module scheme, generic iOS Simulator"
docc_log="$module_root/.build/DocCBuild.log"
xcodebuild \
    -quiet \
    -scheme "$module_name" \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$derived_data" \
    CODE_SIGNING_ALLOWED=NO \
    docbuild 2>&1 | tee "$docc_log"
docc_warnings="$(
    rg -- ': warning:' "$docc_log" \
        | rg -v -- 'SourcePackages/checkouts|Adapty|Swinject|BroadCore' \
        || true
)"
if [[ -n "$docc_warnings" ]]; then
    printf 'BroadMonetization DocC emitted warnings:\n%s\n' "$docc_warnings"
    exit 1
fi

echo "$module_name module gate passed."
echo "No unit/UI tests or real external operations were executed."
