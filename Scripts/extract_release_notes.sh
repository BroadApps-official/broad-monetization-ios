#!/usr/bin/env bash
set -euo pipefail

module_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="${1:-}"
output="${2:-}"

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ || -z "$output" ]]; then
    echo "Usage: bash Scripts/extract_release_notes.sh x.y.z output.md"
    exit 1
fi

temporary_output="$(mktemp)"
trap 'rm -f "$temporary_output"' EXIT

awk -v heading="## $version" '
    $0 == heading { found = 1; print; next }
    found && /^## / { exit }
    found { print }
    END { if (!found) exit 1 }
' "$module_root/CHANGELOG.md" > "$temporary_output" || {
    echo "CHANGELOG has no release section for $version."
    exit 1
}

if [[ "$(wc -l < "$temporary_output")" -lt 3 ]]; then
    echo "Release notes for $version are empty."
    exit 1
fi

mv "$temporary_output" "$output"
echo "Prepared release notes for $version."
