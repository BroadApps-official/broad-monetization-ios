# ``BroadMonetization``

Provider-neutral monetization contracts and production adapters for BroadApps iPhone applications.

## Topics

### Paywalls and products

- ``PaywallPayload``
- ``MonetizationProduct``
- ``LoadPaywallUseCase``
- ``PaywallRemoteConfigurationProvenance``

### Special Offer

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
