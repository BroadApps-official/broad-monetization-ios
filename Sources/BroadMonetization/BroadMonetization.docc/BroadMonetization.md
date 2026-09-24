# ``BroadMonetization``

Provider-neutral monetization contracts and production adapters for BroadApps iPhone applications.

Since 2.0.1, Remote Config comes from the selected paywall of the requested
placement. Main supplies only missing key groups; explicit false, null and
malformed values in the current placement are never replaced. Experiment and
segment codes form one assignment and are never mixed between variants.
Products, variation, purchase handles and shown analytics belong to the actual
paywall. Token IDs try the configured spelling first, then token/tokens when
no paywall is returned. Neither spelling falls back to subscription products.
Custom repositories preserve the same configuration contract and report provenance
honestly; an SDK response that can use cache does not prove fresh backend state.

Since 4.0.1, consumable fulfillment captures the verified StoreKit JWS directly
from the Adapty/StoreKit purchase result before provider auto-finish can remove it
from iOS 17 transaction history. ``AppleTransactionUpdatesBridge`` delivers and
briefly buffers the same evidence for Ask-to-Buy and other out-of-band completions,
including updates received before ``TokenPurchaseManager`` is composed. StoreKit
unfinished/history scans remain recovery fallbacks, not the normal proof path.
The bridge buffer is process-local. Hosts that enable finished-consumable history
must reconcile transaction IDs on their backend before granting tokens again.
Token fulfillment must use the exact transaction ID, not a change in total balance.

After a provider-confirmed Apple subscription, the durable intent enters
`transactionConfirmed` before the entitlement refresh. A later refresh can finish
the attempt without repeating a timestamp-based transaction history match.
Pending and outcome-unknown attempts still require verified StoreKit evidence.
Typed Adapty and StoreKit cancellation or definitive purchase-call rejection
clears the durable intent and permits an immediate retry. This includes
StoreKit 2 errors and nested StoreKit errors wrapped by Adapty. Network and
unknown failures retain the blocker because a charge may already exist.
For a StoreKit premium entitlement source, pass the same
``ApplePremiumProductCatalog`` to `AdaptyMonetizationFactory.makeServices`.
This rejects a remote paywall product before payment when entitlement cannot
recognize its SKU or kind.

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
- ``PendingPurchaseDiagnostic``
- ``PendingApplePurchaseStore``
- ``PendingTokenPurchaseStore``
- ``TokenFulfillmentOutcome``
- ``TokenFulfillmentRepositoryProtocol``
- ``AppleTransactionUpdatesBridge``
- ``Storefront``

### Composition

- ``BroadMonetizationAssembly``
- ``AdaptyPlatformConfiguration``
- ``AdaptyPlacementRegistry``
- ``AdaptyMonetizationFactory``
- ``AdaptyAnonymousIdentityProvider``

### Optional providers

RU implementation and UI live in the separate BroadRUBilling package. Base modules do not import it.

- ``AppleCheckoutMethodsUseCase``
- ``CheckoutSelectedProductUseCase``
- ``PaywallLoaderFactoryProtocol``
- ``PaywallViewReportingPolicyProtocol``
- ``ProviderRemoteConfigParserProtocol``
- ``ProviderPaywallAttemptRepositoryProtocol``
