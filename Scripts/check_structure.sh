#!/usr/bin/env bash

set -euo pipefail

module_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failure_count=0

record_failure() {
    printf '%b\n' "$1"
    failure_count=$((failure_count + 1))
}

module_name="$(/usr/bin/ruby -rjson -e 'puts JSON.parse(File.read(ARGV.fetch(0))).fetch("module")' "$module_root/ModuleContract.json")"
sandbox_name="$(/usr/bin/ruby -rjson -e 'puts JSON.parse(File.read(ARGV.fetch(0))).fetch("sandbox")' "$module_root/ModuleContract.json")"

for relative_path in \
    Package.swift \
    ModuleContract.json \
    README.md \
    README.dev.md \
    CHANGELOG.md \
    CONTRIBUTING.md \
    SECURITY.md \
    AGENTS.md \
    "Sources/$module_name" \
    "Sources/$module_name/$module_name.docc/$module_name.md" \
    "Examples/$sandbox_name/project.yml" \
    Scripts/module_gate.sh \
    Scripts/install_build_tools.sh \
    Scripts/check_remote_feature_contracts.sh \
    Scripts/check_adapty_experiment_contracts.sh \
    Scripts/check_special_offer_runtime_contract.sh \
    Scripts/generate_sandbox.sh \
    Scripts/generate_public_api_report.sh \
    Documentation/PublicAPI.md \
    .github/workflows/quality.yml \
    .github/workflows/release.yml
do
    if [[ ! -e "$module_root/$relative_path" ]]; then
        record_failure "Required module repository path is missing: $relative_path"
    fi
done

for dependency_contract in \
    'BroadApps-official/broad-core-ios\.git' \
    'from: "1\.0\.0"' \
    'Swinject/Swinject\.git' \
    'exact: "2\.10\.0"' \
    'adaptyteam/AdaptySDK-iOS\.git' \
    'exact: "3\.17\.3"'
do
    if ! rg -q -- "$dependency_contract" "$module_root/Package.swift"; then
        record_failure "BroadMonetization dependency contract is missing: $dependency_contract"
    fi
done

if ! swift package --package-path "$module_root" dump-package >/dev/null; then
    record_failure "Package.swift cannot be parsed by SwiftPM."
fi

for package_pattern in \
    "name: \"$module_name\"" \
    "\.library\(name: \"$module_name\"" \
    "\.target\(name: \"$module_name\"" \
    '\.iOS\(\.v17\)' \
    'swiftLanguageModes: \[\.v5\]'
do
    if ! rg -q -- "$package_pattern" "$module_root/Package.swift"; then
        record_failure "Package contract is missing: $package_pattern"
    fi
done

forbidden_directories="$({
    find "$module_root" \
        \( -path "$module_root/.git" -o -path "$module_root/.build" -o -path "$module_root/DerivedData" \) -prune \
        -o -type d \( -name Tests -o -name UITests -o -name '*Tests' -o -name '*UITests' \) -print
} || true)"
if [[ -n "$forbidden_directories" ]]; then
    record_failure "Test directories are forbidden:\n$forbidden_directories"
fi

if rg -n -- '\.(testTarget|test)\s*\(' "$module_root/Package.swift"; then
    record_failure "SwiftPM test targets are forbidden."
fi

if rg -n --glob '*.swift' -- '\b(import[[:space:]]+(XCTest|Testing)|@Test\b|XCTestCase\b)' \
    "$module_root/Sources" "$module_root/Examples" "$module_root/Scripts/ContractProbes"; then
    record_failure "XCTest and Swift Testing are forbidden."
fi

unexpected_imports="$(/usr/bin/ruby -rjson -e '
  config = JSON.parse(File.read(ARGV.shift))
  allowed = config.fetch("allowedBroadImports")
  failures = []
  ARGV.each do |root|
    Dir.glob(File.join(root, "**/*.swift")).sort.each do |path|
      File.foreach(path).with_index(1) do |line, line_number|
        next unless (match = line.match(/^\s*import\s+(Broad[A-Za-z0-9_]+)/))
        failures << "#{path}:#{line_number}: #{match[1]}" unless allowed.include?(match[1])
      end
    end
  end
  puts failures
  exit(failures.empty? ? 0 : 1)
' "$module_root/ModuleContract.json" "$module_root/Sources")" || {
    record_failure "Forbidden BroadApps imports:\n$unexpected_imports"
}

absolute_paths="$(rg -n --glob '!Documentation/PublicAPI.md' --glob '!check_structure.sh' -- '(/Users/|/Volumes/|file://)' \
    "$module_root/README.md" \
    "$module_root/README.dev.md" \
    "$module_root/Documentation" \
    "$module_root/Sources" \
    "$module_root/Examples" \
    "$module_root/Scripts" || true)"
if [[ -n "$absolute_paths" ]]; then
    record_failure "Machine-specific absolute paths are forbidden:\n$absolute_paths"
fi

secret_pattern="(-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----|sk_(live|test)_[A-Za-z0-9]{12,}|(api[_-]?key|secret|token|password)\\s*[:=]\\s*[\"'][A-Za-z0-9_\\-]{16,}[\"'])"
secret_matches="$(rg -n -i --pcre2 \
    "$secret_pattern" \
    "$module_root/Sources" \
    "$module_root/Examples" \
    "$module_root/Documentation" \
    "$module_root/README.md" \
    "$module_root/README.dev.md" || true)"
if [[ -n "$secret_matches" ]]; then
    record_failure "Potential secrets detected:\n$secret_matches"
fi

if ((failure_count > 0)); then
    echo "Module structure validation failed: $failure_count issue(s)."
    exit 1
fi

echo "$module_name repository structure is valid."
