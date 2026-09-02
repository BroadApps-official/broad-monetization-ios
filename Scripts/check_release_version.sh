#!/usr/bin/env bash

set -euo pipefail

module_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
changelog="$module_root/CHANGELOG.md"
readme="$module_root/README.md"

declared_version="$(
    awk '/^## [0-9]+\.[0-9]+\.[0-9]+([[:space:]]|$)/ { print $2; exit }' "$changelog"
)"
expected_version="${1:-$declared_version}"

if [[ ! "$expected_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Release version must be x.y.z: $expected_version"
    exit 1
fi

if [[ "$declared_version" != "$expected_version" ]]; then
    echo "CHANGELOG declares $declared_version, but release tag is $expected_version."
    exit 1
fi

for marker in     "Release $expected_version"     "release-$expected_version-"     "from: \"$expected_version\""
do
    if ! rg -Fq -- "$marker" "$readme"; then
        echo "README release metadata is missing: $marker"
        exit 1
    fi
done

echo "Release metadata is consistent for $expected_version."

