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
- ``ServerSynchronizedSpecialOfferClock``
- ``HTTPServerDate``

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
- ``FlatRUCatalogResponseDecoder``
- ``RUBillingWireAdapters``

### Composition

- ``BroadMonetizationAssembly``
- ``AdaptyPlatformConfiguration``
- ``AdaptyPlacementRegistry``
- ``AdaptyMonetizationFactory``
- ``AdaptyAnonymousIdentityProvider``
