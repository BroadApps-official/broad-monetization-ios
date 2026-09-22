# ``BroadMonetization``

RU checkout can use fresh account policy without a payment-status endpoint.
Omit ``RUBillingEndpointConfiguration/paymentStatus`` to select this mode.
``RUAccountCheckoutExpectation`` persists the token balance captured before checkout.
Call ``RUPaymentReturnCoordinator/applicationDidBecomeActive()`` after payment-page dismissal or foreground return.
``RUPaymentReturnOutcome/tokensCredited(_:)`` updates balance without granting premium.
For an explicitly abandoned checkout, inject
``RUCheckoutTerminationClientProtocol`` and call
``RUPendingCheckoutTerminationCoordinator/terminatePendingCheckout()``. The
durable blocker is removed only after the backend returns a terminal status.

Provider-neutral monetization contracts and production adapters for BroadApps iPhone applications.

Since 2.0.1, Remote Config comes from the selected paywall of the requested
placement. Main supplies only missing key groups; explicit false, null and
malformed values in the current placement are never replaced. Experiment and
segment codes form one assignment and are never mixed between variants.
Products, variation, purchase handles and shown analytics belong to the actual
paywall. Token IDs try the configured spelling first, then token/tokens when
no paywall is returned. Neither spelling falls back to subscription products.
Custom repositories preserve the same configuration contract and report provenance
honestly; an SDK response that can use cache does not prove RU freshness.

Since 4.0.1, consumable fulfillment captures the verified StoreKit JWS directly
from the Adapty/StoreKit purchase result before provider auto-finish can remove it
from iOS 17 transaction history. ``AppleTransactionUpdatesBridge`` delivers and
briefly buffers the same evidence for Ask-to-Buy and other out-of-band completions,
including updates received before ``TokenPurchaseManager`` is composed. StoreKit
unfinished/history scans remain recovery fallbacks, not the normal proof path.

## Topics

### Paywalls and products

- ``PaywallPayload``
- ``MonetizationProduct``
- ``LoadPaywallUseCase``
- ``PaywallRemoteConfigurationProvenance``

### Special Offer

The canonical placement is `special_offer`. When its persisted state is absent,
``PersistedSpecialOfferStateRepository`` imports a matching `special-offer`
configuration without changing active-window or cooldown dates. Existing canonical
state always wins. Resets leave a durable eligible marker so an old snapshot cannot
restore a cleared cycle after relaunch; storage failures remain unavailable.

- ``ResolveSpecialOfferUseCase``
- ``SpecialOfferResolution``
- ``SpecialOfferPresentationAuthorization``
- ``SpecialOfferCountdownAuthorization``
- ``SpecialOfferCoordinator``
- ``SpecialOfferAnalyticsRelay``
- ``SpecialOfferCoordinator``
- ``SpecialOfferAnalyticsRelay``

### Special Offer campaign

- ``ResolveSpecialOfferCampaignUseCase``
- ``SpecialOfferCampaignConfiguration``
- ``SpecialOfferCampaign``
- ``SpecialOfferCampaignOutcome``
- ``SpecialOfferCadence``
- ``SpecialOfferCampaignCoordinator``
- ``SpecialOfferCampaignAnalyticsRelay``
- ``PersistedSpecialOfferWindowStore``

### Entitlements and checkout

- ``EntitlementEngine``
- ``EntitlementStatus``
- ``ProfileIdentityProviderProtocol``
- ``AdaptySDKProfileIdentityProvider``
- ``SubscriptionPurchaseManager``
- ``TokenPurchaseManager``
- ``TokenFulfillmentOutcome``
- ``TokenFulfillmentRepositoryProtocol``
- ``AppleTransactionUpdatesBridge``
- ``RUBillingGate``
- ``RUBillingDeviceContext``
- ``Storefront``
- ``RUCatalogProduct``
- ``RUCatalogSections``
- ``ResolveRUCatalogProductUseCase``
- ``ResolveRUSpecialOfferProductUseCase``
- ``ResolveRUSpecialOfferProductUseCase``
- ``FlatRUCatalogResponseDecoder``
- ``RUBillingWireAdapters``
- ``RUCheckoutTerminationClientProtocol``
- ``RUPendingCheckoutTerminationCoordinator``
- ``RUPendingCheckoutTerminationOutcome``

### RU Billing experiments

- ``RUExperimentMetadata``
- ``RUExperimentEvent``
- ``RUExperimentAssignedSegment``
- ``RUExperimentAssignOutcome``
- ``RUExperimentShownOutcome``
- ``RUExperimentTrackingOutcome``
- ``RUExperimentRepositoryProtocol``
- ``RUExperimentHTTPConfiguration``
- ``URLSessionRUExperimentRepository``
- ``RUBillingExperimentTracker``
- ``RUExperimentCatalogSelector``
- ``RUExperimentCatalogSelection``
- ``RUExperimentCatalogSelectionSource``
- ``RUExperimentCatalogKind``

### Composition

- ``BroadMonetizationAssembly``
- ``AdaptyPlatformConfiguration``
- ``AdaptyPlacementRegistry``
- ``AdaptyMonetizationFactory``
- ``AdaptyAnonymousIdentityProvider``

### RU provider outage fallback

Explicitly opt in with ``LoadPaywallWithRUFallbackUseCase`` or the composition
factory. A Russian Storefront or device region can qualify when the provider
returns no configuration or cannot load products. A received false, invalid or
absent flag closes this path. No capability is persisted; checkout and Premium
still require the backend. Existing APIs keep their previous behavior.

- ``LoadPaywallWithRUFallbackUseCase``
- ``RUFallbackPaywallRepositoryProtocol``
- ``RUFallbackPaywallAttempt``
- ``FreshRUCatalogRepositoryProtocol``

`tokens` and `special_offer` keep their own products and prices. Neither loader
substitutes `main` or the ordinary RU subscription catalog for these placements.

Since 1.5.3, a successful empty provider product array also triggers the opt-in
RU catalog when either the device region or Storefront is Russian. A received
false, missing or invalid `ru_pay` remains a prohibition.

Since 1.5.4, the opt-in loader uses ``RUExperimentCatalogSelector`` to display
all default subscriptions when the provider is unavailable, empty, or has no
exact backend ID matches. Without defaults, the complete subscription section
remains the compatibility fallback. Any exact match keeps the provider payload;
defaults are never attached to a mismatched Apple card. Live nonempty provider
products require the existing fresh RU gate before backend selection. Selected
backend rows retain their original indices and terms for fresh checkout validation.
