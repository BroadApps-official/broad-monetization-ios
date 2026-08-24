#!/usr/bin/env bash

set -euo pipefail

platform_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failure_count=0

require_pattern() {
    local description="$1"
    local file="$2"
    local pattern="$3"
    local status=0

    rg -q --pcre2 --multiline "$pattern" "$file" || status=$?
    case "$status" in
        0)
            echo "PASS: $description"
            ;;
        1)
            echo "FAIL: $description"
            echo "      $file"
            failure_count=$((failure_count + 1))
            ;;
        *)
            echo "Adapty experiment check could not run: $description"
            exit "$status"
            ;;
    esac
}

forbid_pattern() {
    local description="$1"
    local pattern="$2"
    shift 2
    local output=""
    local status=0

    output="$(rg -n --pcre2 --multiline "$pattern" "$@")" || status=$?
    case "$status" in
        0)
            echo "FAIL: $description"
            echo "$output"
            failure_count=$((failure_count + 1))
            ;;
        1)
            echo "PASS: $description"
            ;;
        *)
            echo "Adapty experiment check could not run: $description"
            exit "$status"
            ;;
    esac
}

analytics_file="$platform_root/Sources/BroadMonetization/Domain/Analytics/MonetizationAnalyticsEvent.swift"
factory_file="$platform_root/Sources/BroadMonetization/Application/DI/AdaptyMonetizationFactory.swift"
load_file="$platform_root/Sources/BroadMonetization/Application/Paywalls/LoadPaywallUseCase.swift"
payload_file="$platform_root/Sources/BroadMonetization/Domain/Paywalls/PaywallPayload.swift"
purchase_file="$platform_root/Sources/BroadMonetization/Data/Adapty/AdaptyPurchaseRepository.swift"
registry_file="$platform_root/Sources/BroadMonetization/Infrastructure/Adapty/AdaptyProductRegistry.swift"
repository_file="$platform_root/Sources/BroadMonetization/Data/Adapty/AdaptyPaywallRepository.swift"
track_file="$platform_root/Sources/BroadMonetization/Application/Analytics/TrackMonetizationEvents.swift"

echo "Adapty experiment contract matrix"

require_pattern \
    "Adapty variation enters the provider-neutral paywall payload" \
    "$repository_file" \
    'variationID:[[:space:]]*PaywallVariationID\.optional\(paywall\.variationId\)'

require_pattern \
    "Paywall show analytics keeps the payload variation" \
    "$analytics_file" \
    'variationID[[:space:]]*=[[:space:]]*paywall\.variationID'

require_pattern \
    "Product selection keeps the same paywall variation" \
    "$platform_root/Sources/BroadMonetization/Domain/Checkout/CheckoutModels.swift" \
    'paywallVariationID[[:space:]]*=[[:space:]]*paywall\.variationID'

require_pattern \
    "Purchase analytics reads attribution from the exact selection" \
    "$analytics_file" \
    'paywallVariationID[[:space:]]*=[[:space:]]*selection\.paywallVariationID(?s:.*?)requestedPlacementID[[:space:]]*=[[:space:]]*selection\.requestedPlacementID(?s:.*?)resolvedPlacementID[[:space:]]*=[[:space:]]*selection\.resolvedPlacementID'

require_pattern \
    "Every non-main placement has the common main fallback" \
    "$payload_file" \
    'fallbackPlacementID[[:space:]]*=[[:space:]]*\.main'

require_pattern \
    "Fallback preserves requested and resolved placements and uses the resolved payload variation" \
    "$load_file" \
    'variationID:[[:space:]]*paywall\.variationID(?s:.*?)requestedPlacementID:[[:space:]]*requestedPlacementID(?s:.*?)resolvedPlacementID:[[:space:]]*resolvedPlacementID'

require_pattern \
    "One presentation reserves at most one provider show before awaiting the SDK" \
    "$registry_file" \
    '!entry\.hasReservedShow(?s:.*?)entry\.hasReservedShow[[:space:]]*=[[:space:]]*true(?s:.*?)entries\[presentationID\][[:space:]]*=[[:space:]]*entry(?s:.*?)return[[:space:]]+entry\.paywall'

require_pattern \
    "A repeated display creates a fresh presentation and fresh product occurrence IDs" \
    "$payload_file" \
    'func[[:space:]]+preparedForNewPresentation\(\)(?s:.*?)PaywallPresentationID\.generated\(\)(?s:.*?)replacingPresentationID\(with:[[:space:]]*\.generated\(\)\)'

require_pattern \
    "Concurrent Adapty loads clone one raw cohort into unique presentations" \
    "$repository_file" \
    'clonePresentation\((?s:.*?)from:[[:space:]]*paywall\.presentationID(?s:.*?)to:[[:space:]]*uniquePaywall\.presentationID'

forbid_pattern \
    "Cached payload loading never invents a provider impression" \
    'presentationDidAppear' \
    "$load_file"

require_pattern \
    "A provider show is attempted only after a real paywall-shown event" \
    "$track_file" \
    'case[[:space:]]+let[[:space:]]+\.paywallShown\(context\):(?s:.*?)presentationDidAppear\(context\)'

require_pattern \
    "Evicted raw products require exact variation and provider-array index" \
    "$purchase_file" \
    'paywall\.variationID[[:space:]]*==[[:space:]]*selection\.paywallVariationID(?s:.*?)paywall\.products\.indices\.contains\(selection\.productIndex\)'

require_pattern \
    "Evicted raw products require exact SKU and commercial fingerprint" \
    "$purchase_file" \
    'rehydratedProduct\.productID[[:space:]]*==[[:space:]]*selection\.product\.productID(?s:.*?)rehydratedProduct\.commercialFingerprint[[:space:]]*==[[:space:]]*expectedFingerprint'

require_pattern \
    "One factory-owned identity provider is shared by load, show, purchase and restore" \
    "$factory_file" \
    'private[[:space:]]+let[[:space:]]+identityProvider:[[:space:]]*any[[:space:]]+AdaptyIdentityProviderProtocol(?s:.*?)AdaptyPaywallPresentationLifecycle\((?s:.*?)identityProvider:[[:space:]]*identityProvider(?s:.*?)AdaptyPaywallRepository\((?s:.*?)identityProvider:[[:space:]]*identityProvider(?s:.*?)AdaptyPurchaseRepository\((?s:.*?)identityProvider:[[:space:]]*identityProvider(?s:.*?)AdaptyRestoreRepository\((?s:.*?)identityProvider:[[:space:]]*identityProvider'

forbid_pattern \
    "Platform contains no second experiment assignment or randomizer" \
    '(?i)\b(ExperimentAssignment|CohortAssignment|SegmentAssignment|ExperimentRandomizer|CohortRandomizer|ClientSideRandomizer)\b' \
    "$platform_root/Sources" \
    --glob '*.swift'

forbid_pattern \
    "uiVariant metadata never participates in Adapty assignment" \
    'uiVariantID' \
    "$platform_root/Sources/BroadMonetization/Data/Adapty" \
    "$platform_root/Sources/BroadMonetization/Infrastructure/Adapty"

if ((failure_count > 0)); then
    echo "Adapty experiment contract matrix failed: $failure_count item(s)."
    exit 1
fi

echo "Adapty experiment contract matrix passed."
