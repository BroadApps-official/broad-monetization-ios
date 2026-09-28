# Standard Special Offer preparation

Call `prepare(configuration:)` after showing the ordinary subscription paywall,
while the user is deciding whether to buy. Await it in a task owned by that
screen. A dismissed paywall without a confirmed purchase then calls the resolver
with the same configuration, or sends the close event to `SpecialOfferCoordinator`.

```swift
let configuration = SpecialOfferConfiguration(
    placementID: .specialOffer,
    gatePlacementID: .main
)

// While the ordinary paywall is visible:
await resolveSpecialOffer.prepare(configuration: configuration)

// After dismissal without a confirmed purchase:
let decision = await resolveSpecialOffer(configuration: configuration)
if case .active = decision.state, let paywall = decision.paywall {
    // Present this paywall, then report its actual presentation through the app flow.
    showSpecialOffer(paywall)
}
```

`prepare` loads and parses every product in the selected gate paywall before
reading a strict `special_offer == true` value. Missing keys can fall back to
`main`; explicit false, invalid, or null values cannot. Platform persistent
cache cannot enable the gate. It then loads every product from the separate
offer placement, with no substitution from `main`, and checks the offer's own
flag and provenance. The prepared paywalls are held for at most ten minutes.
Another preparation replaces them. A reset, active entitlement, expiry, or
rejected decision ends unused presentations.

Preparation does not read or write the persisted cycle, request trusted time,
or count an impression. Resolution after dismissal checks entitlement, trusted
time, the 24-hour window and 24-hour cooldown, then validates the flags before
returning the offer. The window begins only at that resolution. Without a fresh
preparation for the same configuration, resolution loads both placements as
before. Confirmed purchase and restore still call `resetCycle` through the
coordinator or the host flow.

In DEBUG, a returned Adapty paywall whose vendor product IDs are missing from
`getPaywallProducts` produces a platform warning with the logical placement,
matched and expected counts, and missing IDs. Add those IDs to the app's Debug
`.storekit` file with App Store prices. Release behavior is unchanged.

This additive public API has **minor SemVer intent**. Existing custom
`ResolveSpecialOfferUseCaseProtocol` implementations keep compiling through its
default no-op `prepare` implementation.
