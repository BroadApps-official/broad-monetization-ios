# Optional payment providers in 5.0

The Apple-only graph is BroadUIFlows → BroadMonetization → BroadCore.
It does not depend on BroadRUBilling, including through an umbrella package.
Use BroadCore 3.0.0, BroadMonetization 5.0.0 and BroadUIFlows 5.0.0 together.

Install the optional [BroadRUBilling package](https://github.com/BroadApps-official/broad-ru-billing-ios)
only in app targets that use Russian payments. Its `BroadRUBilling` product owns
catalog, HTTP, account-policy reconciliation, pending storage, callbacks and
experiment reporting; `BroadRUBillingUI` adds payment and subscription screens.

## Base composition

Use `AppleCheckoutMethodsUseCase` and
`CheckoutSelectedProductUseCase(applePurchase: services.purchaseProduct)`.
There is no disabled RU service to instantiate in an Apple-only app.

## Provider extension points

- `CheckoutMethod`, `CatalogSource`, `EntitlementSource` and operation identifiers
  are extensible string values. Codable retains the previous single-string wire
  format. Update exhaustive switches with a fail-closed default.
- `CheckoutMethodsResolution` and `CheckoutOptions` carry opaque provider data
  with an explicit provider ID. Only the installed provider interprets it.
- `ProviderRemoteConfigParserProtocol` owns provider keys. Atomic alias
  groups preserve explicit false/invalid/null against main-key fallback. Extension
  configuration is response-local and is dropped on persistence round trips.
- `PaywallLoaderFactoryProtocol` receives the actual provider attempt, including
  configuration received before product loading failed.
- `PaywallViewReportingPolicyProtocol` reserves a single reporting destination
  before dismissal. A failed external report never falls through to primary SDK
  analytics.
- Every provider receives the exact same `MonetizationOperationGate` instance.
  Register durable blockers before exposing purchase/restore to callers.

## Migration of RU apps

Add `import BroadRUBilling`, and `import BroadRUBillingUI` for presentation.
Install `RUBillingRemoteConfigurationParser` in the parser passed to the Adapty
factory. Pass the RU composition as `paywallLoaderFactory`, its experiment tracker
as `viewReporting`, and a `RUBillingCheckoutAdapter` as `additionalCheckout`.
Replace `BroadPaywallView` with `BroadRUPaywallView` and pass RU UI configuration
to that view. Subscription status recovery now wraps the base recovery with
`RecoverRUCustomerAccessUseCase`.

Keep application ID, account subject and storage repositories unchanged. The RU
package preserves pending record keys, schema and raw identifiers. Existing
`awaitingReconciliation` attempts remain recoverable after the package migration.
Handle foreground, callback URL and browser dismissal only in RU-enabled targets.
Closing a page or finishing local polling does not cancel a financial payment.
