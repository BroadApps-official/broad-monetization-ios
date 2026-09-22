#!/usr/bin/env bash
set -euo pipefail
module_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if rg -n --glob '*.swift' 'BroadRUBilling|RUBilling|RUCheckout|RUCatalog|ru_pay|russian_payment|ukassa|\bsbp\b' "$module_root/Sources" "$module_root/Package.swift"; then
    echo 'Base monetization must not contain or depend on the optional RU provider.'
    exit 1
fi
if rg -n 'broad-ru-billing-ios' "$module_root/Package.swift"; then exit 1; fi
echo 'Base monetization has no RU implementation or package dependency.'
