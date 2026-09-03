#!/usr/bin/env bash

set -euo pipefail

platform_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT

xcrun swiftc \
    "$platform_root/Sources/BroadMonetization/Domain/Identifiers/MonetizationIdentifiers.swift" \
    "$platform_root/Sources/BroadMonetization/Domain/SpecialOffers/SpecialOfferModels.swift" \
    "$platform_root/Sources/BroadMonetization/Domain/SpecialOfferCampaigns/SpecialOfferCampaignModels.swift" \
    "$platform_root/Sources/BroadMonetization/Domain/SpecialOfferCampaigns/SpecialOfferCadence.swift" \
    "$platform_root/Scripts/ContractProbes/SpecialOfferCampaignProbe.swift" \
    -o "$temporary_directory/special-offer-campaign-probe"

"$temporary_directory/special-offer-campaign-probe"
