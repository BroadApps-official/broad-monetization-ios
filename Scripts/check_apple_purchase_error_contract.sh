#!/usr/bin/env bash
set -euo pipefail

module_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
probe_directory="$(mktemp -d)"
trap 'rm -rf "$probe_directory"' EXIT
host_arch="$(uname -m)"

xcrun swiftc -target "${host_arch}-apple-macos15.0" \
    -parse-as-library -strict-concurrency=complete -warnings-as-errors \
    "$module_root/Sources/BroadMonetization/Infrastructure/ApplePurchases/ApplePurchaseErrorClassifier.swift" \
    "$module_root/Scripts/ContractProbes/ApplePurchaseErrorProbe.swift" \
    -o "$probe_directory/apple-purchase-error-probe"
"$probe_directory/apple-purchase-error-probe"
