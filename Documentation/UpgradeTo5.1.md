# BroadMonetization 5.1.0: upgrade guide

This guide covers an app already using the 5.0.0 platform set. The published
compatible set remains authoritative; do not change a production app's package
pins until the new set appears in
[Compatibility/current.yml](https://github.com/BroadApps-official/broad-platform-integration/blob/main/Compatibility/current.yml).
An app still pinned to 1.x must first follow the
[multi-module migration guide](https://github.com/BroadApps-official/broad-platform-integration/blob/main/Documentation/MigrationGuide.md).
Updating BroadMonetization alone cannot bridge the 1.x to 5.x changes in Core,
UIFlows or app composition.

## What changes after updating the package

- Typed StoreKit cancellation and definitive purchase-call refusal release the
  durable Apple purchase blocker, allowing another tap. Unknown, network and
  deferred outcomes continue to wait for verified reconciliation.
- A provider-confirmed subscription stores its confirmed phase before
  entitlement refresh. Foreground recovery retries the entitlement check even
  when a second matching transaction is absent from history.
- Support diagnostics can describe a pending Apple or token purchase without
  including receipt, JWS, user ID or payment details.
- Existing factory calls and purchase initializer signatures still compile.
  The new premium catalog check is opt-in.

## Host actions

1. Keep the same application identifier, entitlement subject and pending-store
   persistence. Do not clear UserDefaults or Keychain during migration.
2. If the app uses a StoreKit premium entitlement catalog, pass that same
   `ApplePremiumProductCatalog` to
   `AdaptyMonetizationFactory.makeServices(..., premiumProductCatalog:)`.
   This refuses an unsupported premium SKU before StoreKit starts a charge.
3. Add `diagnosticSnapshot()?.supportText` to the app's support action if it
   shows pending purchases. Send no raw error, receipt or signed transaction.
4. For consumables, keep backend fulfillment idempotent by StoreKit transaction
   ID. The backend must return the result for that transaction and account;
   total balance changes are insufficient proof.
5. Update the app's exact package requirements and `Package.resolved` together,
   using the published compatible set. Build Debug and Release, then review
   cancellation, definitive refusal, pending approval, entitlement refresh,
   restart, account switch and token fulfillment with the app's own adapters.

## Existing pending attempts and rollback

An attempt stored by an older version as `outcomeUnknown` has no recorded
terminal StoreKit error. One empty history scan or elapsed time does not prove
that the customer was not charged. The update therefore keeps this blocker
until a verified transaction or support investigation resolves it.

To revert the app, restore the previous exact package requirements and
`Package.resolved` in one commit and rebuild. A package rollback cannot undo
backend credit or change an already recorded purchase. Preserve pending data.

## Validation scope

The module gate and candidate consumer builds cover compilation, public API
and executable contract probes. They do not perform a real App Store payment,
Adapty backend validation or an app-specific webhook. Local StoreKit Testing
in Xcode can exercise the host purchase UI without a Sandbox account, but its
transactions do not establish production backend behavior.
