# BroadMonetization

Provider-neutral monetization-модуль BroadApps для paywall catalog,
Adapty/StoreKit adapters, entitlements, purchase/restore coordination, Special
Offer, RU Billing и safe analytics.

[Документация BroadApps iOS](https://broadapps-ios-docs.nkhsnv.chatgpt.site) ·
[Changelog](CHANGELOG.md) ·
[Публичный API](Documentation/PublicAPI.md) ·
[Как предложить правку](CONTRIBUTING.md)

## Что делает модуль

- загружает paywall и все products в provider order без filter/sort/dedup;
- сохраняет exact raw-product reference для purchase;
- агрегирует server-authoritative entitlement sources и bounded cache;
- координирует purchase/restore/recovery без дублирования operations;
- применяет fail-closed gates для Special Offer и RU Billing;
- регистрирует dependencies через `BroadMonetizationAssembly`.

## Что модуль не делает

- не содержит готовые SwiftUI paywall/onboarding screens;
- не хранит app-owned keys, product IDs, placement IDs и backend URLs;
- не признаёт cache доказательством purchase или premium access;
- не запускает purchase, restore и RU payment в sandbox/gate;
- не зависит от `BroadUIFlows` или `BroadExtensions`.

## Product и dependencies

| Product | Platform | BroadApps dependency | External dependencies |
|---|---|---|---|
| `BroadMonetization` | iOS 17+, iPhone | compatible `BroadCore` from `1.0.0` | Adapty `3.17.3`, Swinject `2.10.0` |

Host app подключает этот repository только по надобности. Обязательного
umbrella package нет. Если app напрямую импортирует `BroadCore`, его product
тоже добавляется в app target.

## Installation

```swift
dependencies: [
    .package(
        url: "https://github.com/BroadApps-official/broad-monetization-ios.git",
        from: "1.0.0"
    )
]
```

## Special Offer: где теперь стоит gate

Претензия «блок идёт до парсинга подписок» закрыта явным pipeline:

```text
Adapty.getPaywall
  → Adapty.getPaywallProducts
  → mapping всего provider array без filter/sort/dedup
  → storage exact raw-product references
  → Special Offer provenance + special_offer gate
  → presentation authorization
```

`ResolveSpecialOfferUseCase` получает уже целый `PaywallPayload` с products и
только после этого проверяет `special_offer = true`. Current provider
payload, включая provider-managed fallback/cache, может разрешить
Special Offer. BroadMonetization platform cache не может заново включить
его. RU Billing остаётся строже и требует verified-fresh payload.

24-часовой countdown — только visual loop
`24:00:00 → 00:00:00 → 24:00:00`; ноль не скрывае offer и не блокирует
purchase.

## Safe integration boundary

Host передаёт configuration и backend implementations через public
protocols/factories. Production composition собирается снизу вверх:

```swift
let assemblies = [
    BroadCoreAssembly(/* app-owned dependencies */),
    BroadMonetizationAssembly(/* app-owned dependencies */)
]
```

## Contract checks

```bash
bash Scripts/check_remote_feature_contracts.sh
bash Scripts/check_adapty_experiment_contracts.sh
bash Scripts/check_special_offer_runtime_contract.sh
```

Проверки компилируют production types и фиксируют order/provenance,
product identity, Special Offer countdown и RU fail-closed contracts без
XCTest/Swift Testing.

## Sandbox

```bash
bash Scripts/generate_sandbox.sh
open Examples/BroadMonetizationSandbox/BroadMonetizationSandbox.xcodeproj
```

Sandbox показывает fixture products, parsed remote flags, Special Offer/RU
authority и countdown. Он не активирует SDK и не вызывает financial
operations.

## Проверка

```bash
bash Scripts/module_gate.sh
```

Gate проверяет dependencies/boundaries, secrets, format/lint, Swift package,
Special Offer/remote/Adapty contracts, public API report, Debug/Release sandbox и
DocC. Test targets не создаются, реальные payment operations не запускаются.

## Versioning

Модуль выпускается независимо по SemVer. `BroadCore` указан compatible
major range; integration catalog фиксирует exact known-good combination.

## Documentation

- [Module guide](Documentation/BroadMonetization.md);
- [DocC landing](Sources/BroadMonetization/BroadMonetization.docc/BroadMonetization.md);
- [Public searchable docs](https://broadapps-ios-docs.nkhsnv.chatgpt.site/docs/broad-monetization).

Документы публичны и принимают правки через pull request / `Edit this page`.
