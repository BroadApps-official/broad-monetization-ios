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
            echo "Remote feature contract check could not run: $description"
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
            echo "Remote feature contract check could not run: $description"
            exit "$status"
            ;;
    esac
}

provenance_file="$platform_root/Sources/BroadMonetization/Domain/Paywalls/PaywallRemoteConfigurationProvenance.swift"
configuration_file="$platform_root/Sources/BroadMonetization/Domain/Paywalls/RemotePaywallConfiguration.swift"
adapty_repository_file="$platform_root/Sources/BroadMonetization/Data/Adapty/AdaptyPaywallRepository.swift"
purchase_file="$platform_root/Sources/BroadMonetization/Data/Adapty/AdaptyPurchaseRepository.swift"
registry_file="$platform_root/Sources/BroadMonetization/Infrastructure/Adapty/AdaptyProductRegistry.swift"
load_file="$platform_root/Sources/BroadMonetization/Application/Paywalls/LoadPaywallUseCase.swift"
last_valid_file="$platform_root/Sources/BroadMonetization/Data/Paywalls/LastValidRemoteConfigurationStore.swift"
special_use_case_file="$platform_root/Sources/BroadMonetization/Application/SpecialOffers/ResolveSpecialOfferUseCase.swift"
special_resolution_file="$platform_root/Sources/BroadMonetization/Domain/SpecialOffers/SpecialOfferResolution.swift"
special_countdown_file="$platform_root/Sources/BroadMonetization/Domain/SpecialOffers/SpecialOfferCountdownAuthorization.swift"
special_campaign_file="$platform_root/Sources/BroadMonetization/Application/SpecialOfferCampaigns/ResolveSpecialOfferCampaignUseCase.swift"
remote_parser_file="$platform_root/Sources/BroadMonetization/Infrastructure/RemoteConfig/RemotePaywallConfigurationParser.swift"
ru_gate_file="$platform_root/Sources/BroadMonetization/Application/RUBilling/RUBillingGate.swift"
ru_device_context_file="$platform_root/Sources/BroadMonetization/Domain/Checkout/RUBillingDeviceContext.swift"
ru_debug_override_file="$platform_root/Sources/BroadMonetization/Application/RUBilling/RUBillingDebugOverride.swift"
ru_resolution_file="$platform_root/Sources/BroadMonetization/Application/RUBilling/ResolveCheckoutMethodsUseCase.swift"
ru_checkout_flow_file="$platform_root/Sources/BroadMonetization/Application/RUBilling/RUCheckoutFlowCoordinator.swift"
ru_flat_catalog_file="$platform_root/Sources/BroadMonetization/Infrastructure/RUBilling/FlatRUCatalogResponseDecoder.swift"
ru_catalog_product_file="$platform_root/Sources/BroadMonetization/Domain/Checkout/RUCatalogProduct.swift"
ru_catalog_matcher_file="$platform_root/Sources/BroadMonetization/Application/RUBilling/RUCatalogProductMatcher.swift"
ru_composition_models_file="$platform_root/Sources/BroadMonetization/Application/DI/RUBillingCompositionModels.swift"
ru_composition_factory_file="$platform_root/Sources/BroadMonetization/Application/DI/RUBillingCompositionFactory.swift"
adapty_configuration_file="$platform_root/Sources/BroadMonetization/Infrastructure/Adapty/AdaptyPlatformConfiguration.swift"
adapty_activation_file="$platform_root/Sources/BroadMonetization/Infrastructure/Adapty/AdaptySDKActivationGate.swift"

require_pattern \
    "A current Adapty/provider payload may drive the Special Offer gate" \
    "$provenance_file" \
    'case[[:space:]]+\.verifiedFreshRemote,[[:space:]]+\.providerCacheFallbackPossible:(?s:.*?)[[:space:]]+true'

require_pattern \
    "A BroadMonetization cache or legacy payload cannot enable Special Offer" \
    "$provenance_file" \
    'case[[:space:]]+\.platformCache,[[:space:]]+\.legacyUnqualified:(?s:.*?)[[:space:]]+false'

require_pattern \
    "A current Adapty/provider payload may drive the explicit RU Billing gate" \
    "$provenance_file" \
    'authorizesProviderFeatures:[[:space:]]*Bool[[:space:]]*\{(?s:.*?)case[[:space:]]+\.verifiedFreshRemote,[[:space:]]+\.providerCacheFallbackPossible:(?s:.*?)[[:space:]]+true(?s:.*?)case[[:space:]]+\.platformCache,[[:space:]]+\.legacyUnqualified:(?s:.*?)[[:space:]]+false'

require_pattern \
    "Only a received placement configuration is marked provider-managed" \
    "$adapty_repository_file" \
    'remoteConfigurationProvenance:[[:space:]]*receivedConfiguration[[:space:]]*==[[:space:]]*nil[[:space:]]*\?[[:space:]]*\.legacyUnqualified[[:space:]]*:[[:space:]]*\.providerCacheFallbackPossible'

require_pattern \
    "Adapty obtains all keys through the placement loader with main fallback" \
    "$adapty_repository_file" \
    'placementConfigurationLoader\.load\((?s:.*?)for:[[:space:]]*logicalPlacementID(?s:.*?)parser\.parse\((?s:.*?)paywall\.remoteConfig\?\.dictionary(?s:.*?)fallback:[[:space:]]*main\?\.remoteConfig\?\.dictionary'

require_pattern \
    "Products use the target paywall returned by the placement configuration loader" \
    "$adapty_repository_file" \
    'guard[[:space:]]+let[[:space:]]+paywall[[:space:]]*=[[:space:]]*source\.paywall(?s:.*?)Adapty\.getPaywallProducts\(paywall:[[:space:]]*paywall\)'

require_pattern \
    "Remote configuration strips special_offer when provider authority is absent" \
    "$configuration_file" \
    'specialOffer:[[:space:]]*provenance\.authorizesSpecialOfferPresentation[[:space:]]*\?[[:space:]]*specialOffer[[:space:]]*:[[:space:]]*nil'

require_pattern \
    "Remote configuration resolves provider authority through its independent capability" \
    "$configuration_file" \
    'authorizesProviderFeatures:[[:space:]]*provenance(?s:.*?)\.authorizesProviderFeatures'

require_pattern \
    "Special-offer resolution checks its dedicated provenance capability" \
    "$special_use_case_file" \
    'remoteConfigurationProvenance(?s:.*?)\.authorizesSpecialOfferPresentation'

require_pattern \
    "Special-offer presentation authorization repeats its dedicated guard" \
    "$special_resolution_file" \
    'remoteConfigurationProvenance(?s:.*?)\.authorizesSpecialOfferPresentation'

require_pattern \
    "Special Offer uses only the parsed flag as its campaign gate" \
    "$remote_parser_file" \
    'isEnabled:[[:space:]]*parseSpecialOfferGate\(in:[[:space:]]*dictionary\)'

forbid_pattern \
    "Legacy duration metadata cannot disable Special Offer" \
    'isEnabled:(?s:.{0,250})(windowDuration|cooldownDuration)\.isValid' \
    "$remote_parser_file"

require_pattern \
    "Special Offer reads the configured placement gate before loading offer products" \
    "$special_use_case_file" \
    'PaywallLoadRequest\(placementID:[[:space:]]*configuration\.gatePlacementID\)(?s:.*?)specialOffer\?\.isEnabled[[:space:]]*==[[:space:]]*true'

require_pattern \
    "Special Offer loads the separate product placement only after cadence authorization" \
    "$special_use_case_file" \
    'stateRepository\.state\((?s:.*?)case[[:space:]]+let[[:space:]]+\.active\(window\)(?s:.*?)PaywallLoadRequest\(placementID:[[:space:]]*configuration\.placementID\)'

require_pattern \
    "A current offer prohibition revokes the initial special-offer gate" \
    "$special_use_case_file" \
    'guard[[:space:]]+offerPaywall\.remoteConfiguration\.specialOffer\?\.isEnabled[[:space:]]*==[[:space:]]*true(?s:.*?)resetIfPossible(?s:.*?)disabledByRemoteConfiguration'

require_pattern \
    "Special Offer authorization carries the current offer configuration" \
    "$special_resolution_file" \
    'gateRemoteConfiguration:[[:space:]]*paywall\.remoteConfiguration,[[:space:]]*provenance:[[:space:]]*paywall\.remoteConfigurationProvenance'

require_pattern \
    "Special Offer cadence uses persisted state and trusted time" \
    "$special_use_case_file" \
    'clock\.reading\(\)(?s:.*?)stateRepository\.state\((?s:.*?)stateRepository\.save\(nextState'

require_pattern \
    "An active entitlement is rejected before Special Offer paywall loading" \
    "$special_use_case_file" \
    'entitlementStatusProvider\.currentStatus\(\)[[:space:]]*!=[[:space:]]*\.active(?s:.*?)PaywallLoadRequest'

require_pattern \
    "The campaign compatibility API also reads the gate from the configured placement" \
    "$special_campaign_file" \
    'PaywallLoadRequest\(placementID:[[:space:]]*configuration\.gatePlacementID\)(?s:.*?)specialOffer\?\.isEnabled[[:space:]]*==[[:space:]]*true'

require_pattern \
    "The campaign compatibility API ignores remote duration overrides" \
    "$special_campaign_file" \
    'windowDuration:[[:space:]]*SpecialOfferCampaignConfiguration\.defaultWindowDuration(?s:.*?)cooldownDuration:[[:space:]]*SpecialOfferCampaignConfiguration\.defaultCooldownDuration'

require_pattern \
    "Special Offer fallback cannot substitute the ordinary paywall" \
    "$special_use_case_file" \
    '!origin\.usedFallback(?s:.*?)origin\.requestedPlacementID[[:space:]]*==[[:space:]]*placementID(?s:.*?)origin\.resolvedPlacementID[[:space:]]*==[[:space:]]*placementID'

require_pattern \
    "Special Offer display timer expires at zero" \
    "$special_countdown_file" \
    'remainingTimeInterval[[:space:]]*<=[[:space:]]*0'

forbid_pattern \
    "Special Offer countdown never loops after zero" \
    '(%[[:space:]]*cycleFrameCount|case[[:space:]]+looping|never expires)' \
    "$special_countdown_file"

require_pattern \
    "BroadApps default uses only the exact special_offer gate key" \
    "$platform_root/Sources/BroadMonetization/Infrastructure/RemoteConfig/RemoteConfigKeyRegistry.swift" \
    'specialOfferGate:[[:space:]]*\["special_offer"\]'

require_pattern \
    "Special Offer gate accepts only a Foundation boolean" \
    "$remote_parser_file" \
    'parseStrictBool\(rawValue\)(?s:.*?)isFoundationBoolean\(value\)'

require_pattern \
    "Adapty configuration accepts only a typed local fallback file URL" \
    "$adapty_configuration_file" \
    'public[[:space:]]+let[[:space:]]+fallbackFileURL:[[:space:]]*URL\?(?s:.*?)\$0\.isFileURL[[:space:]]*&&[[:space:]]*\$0\.pathExtension\.lowercased\(\)[[:space:]]*==[[:space:]]*"json"'

require_pattern \
    "Dashboard-generated Adapty fallback is registered before SDK activation" \
    "$adapty_activation_file" \
    'Adapty\.setFallback\(fileURL:[[:space:]]*fallbackFileURL\)(?s:.*?)Adapty\.activate'

require_pattern \
    "Last-valid storage never resurrects old provider or special-offer gates" \
    "$last_valid_file" \
    'specialOffer:[[:space:]]*parsed\.specialOffer(?s:.*?)providerConfigurations:[[:space:]]*parsed\.providerConfigurations'

forbid_pattern \
    "Last-valid storage contains no previous provider/special gate fallback" \
    'previous\?\.(providerConfigurations|specialOffer)' \
    "$last_valid_file"

require_pattern \
    "A paywall restored from the platform cache is downgraded to platformCache" \
    "$load_file" \
    'catalogSource[[:space:]]*==[[:space:]]*\.cache(?s:.*?)\?[[:space:]]*\.platformCache'

require_pattern \
    "Fallback keeps requested and actually resolved placements" \
    "$load_file" \
    'requestedPlacementID:[[:space:]]*requestedPlacementID(?s:.*?)resolvedPlacementID:[[:space:]]*resolvedPlacementID'

require_pattern \
    "Adapty loads the paywall before loading all of its products" \
    "$adapty_repository_file" \
    'Adapty\.getPaywall\((?s:.*?)Adapty\.getPaywallProducts\(paywall:[[:space:]]*paywall\)'

require_pattern \
    "Adapty paywall loading keeps raw products in its internal registry" \
    "$adapty_repository_file" \
    'context\.productRegistry\.store\((?s:.*?)products:[[:space:]]*zip\(mappedProducts,[[:space:]]*adaptyProducts\)'

require_pattern \
    "Adapty purchase resolves the exact selected raw product from that registry" \
    "$purchase_file" \
    'context\.productRegistry\.product\(for:[[:space:]]*selection\)'

require_pattern \
    "The Adapty product registry stays internal to BroadMonetization" \
    "$registry_file" \
    '^actor[[:space:]]+AdaptyProductRegistry'

forbid_pattern \
    "The Adapty data layer contains no custom REST/URLSession transport" \
    '\b(URLSession|URLRequest|URLResponse|HTTPURLResponse)\b' \
    "$platform_root/Sources/BroadMonetization/Data/Adapty" \
    "$platform_root/Sources/BroadMonetization/Infrastructure/Adapty" \
    --glob '*.swift'

forbid_pattern \
    "The platform contains no second client-side experiment randomizer" \
    '(?i)\b(ExperimentAssignment|CohortAssignment|SegmentAssignment|ExperimentRandomizer|CohortRandomizer|ClientSideRandomizer|arc4random|randomElement)\b' \
    "$platform_root/Sources/BroadMonetization" \
    --glob '*.swift'
if ((failure_count > 0)); then exit 1; fi
bash "$platform_root/Scripts/check_special_offer_runtime_contract.sh"
echo "Remote configuration contracts passed."
