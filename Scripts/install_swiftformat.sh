#!/usr/bin/env bash

set -euo pipefail

module_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tool_version="0.62.1"
tool_checksum="7cb1cb1fae04932047c7015441c543848e8e60e1572d808d080e0a1f1661114a"
tool_directory="$module_root/.build/tooling/swiftformat-$tool_version"
tool_binary="$tool_directory/swiftformat"

if [[ -x "$tool_binary" ]] && [[ "$("$tool_binary" --version)" == "$tool_version" ]]; then
    echo "SwiftFormat $tool_version is already installed locally."
    exit 0
fi

temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT
tool_archive="$temporary_directory/swiftformat.zip"
tool_url="https://github.com/nicklockwood/SwiftFormat/releases/download/$tool_version/swiftformat.zip"

curl --fail --location --silent --show-error "$tool_url" --output "$tool_archive"
actual_checksum="$(shasum -a 256 "$tool_archive" | awk '{print $1}')"

if [[ "$actual_checksum" != "$tool_checksum" ]]; then
    echo "SwiftFormat checksum mismatch. Expected $tool_checksum, received $actual_checksum."
    exit 1
fi

mkdir -p "$tool_directory"
unzip -oq "$tool_archive" -d "$tool_directory"

if [[ ! -x "$tool_binary" ]] || [[ "$("$tool_binary" --version)" != "$tool_version" ]]; then
    echo "SwiftFormat $tool_version was downloaded but could not be verified."
    exit 1
fi

echo "SwiftFormat $tool_version installed locally."
