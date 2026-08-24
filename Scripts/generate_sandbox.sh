#!/usr/bin/env bash

set -euo pipefail

module_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sandbox_name="$(/usr/bin/ruby -rjson -e 'puts JSON.parse(File.read(ARGV.fetch(0))).fetch("sandbox")' "$module_root/ModuleContract.json")"
sandbox_root="$module_root/Examples/$sandbox_name"
xcodegen_version="2.45.4"
xcodegen_binary="$module_root/.build/tooling/xcodegen-$xcodegen_version/xcodegen/bin/xcodegen"

bash "$module_root/Scripts/install_build_tools.sh"
"$xcodegen_binary" generate --spec "$sandbox_root/project.yml" --project "$sandbox_root"
echo "$sandbox_name project generated."
