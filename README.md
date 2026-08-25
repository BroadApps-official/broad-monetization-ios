# BroadMonetization

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="Documentation/Assets/README/hero-dark.svg">
    <source media="(prefers-color-scheme: light)" srcset="Documentation/Assets/README/hero-light.svg">
    <img alt="BroadApps iOS Platform" src="Documentation/Assets/README/hero-light.svg" width="100%">
  </picture>
</p>

<p align="center">
  <img alt="iOS 17+" src="https://img.shields.io/badge/iOS-17%2B-111827?logo=apple&amp;logoColor=white">
  <img alt="Swift 5" src="https://img.shields.io/badge/Swift-language%20mode%205-F05138?logo=swift&amp;logoColor=white">
  <img alt="Adapty 3.17.3" src="https://img.shields.io/badge/Adapty-3.17.3-7C3AED">
  <img alt="Release 1.0.0" src="https://img.shields.io/badge/release-1.0.0-10B981">
</p>

Provider-neutral monetization-модуль BroadApps для paywall catalog,
Adapty/StoreKit adapters, entitlements, purchase/restore coordination, Special
Offer, RU Billing и safe analytics.

[Документация BroadApps iOS](https://broadapps-ios-docs.nkhsnv.chatgpt.site) ·
[Создание приложения](https://broadapps-ios-docs.nkhsnv.chatgpt.site/docs/app-creation) ·
[Changelog](CHANGELOG.md) ·
[Публичный API](Documentation/PublicAPI.md) ·
[Как предложить правку](CONTRIBUTING.md)

**Быстрый маршрут:** [установка](#installation) ·
[Adapty setup](#базовая-настройка-adapty) ·
[Special Offer](#special-offer-где-теперь-стоит-gate) ·
[RU Billing](#ru-billing) · [tokens](#token-purchases-и-recovery) ·
[проверка](#проверка)

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

## Базовая настройка Adapty

Реальные keys, product IDs и placement IDs принадлежат host app. Модуль хранит
typed contract и fallback policy, но не вшивает строки конкретного проекта.

| Что настраивается | Базовое правило для нового app |
|---|---|
| Product без trial | Командная naming convention — суффикс `nottrial` слитно, например `weekly_9.99_nottrial`; runtime на имя не полагается |
| Paywall names | `main`; опциональные `tokens` и `special_offer` только когда flow действительно нужен |
| Placement IDs | `onboarding`, `pro_icon`, `settings`, `main`, `CTR`, `special_offer`; дополнительные — из app specification |
| Fallback | Базовые placements связываются с paywall `main`; фактический fallback фиксируется в payload context |
| Products | `getPaywall → getPaywallProducts → 1:1 mapping → raw registry`; без filter/sort/dedup |

Минимальный безопасный Remote Config для **нового приложения с выключенными
опциональными features**:

```json
{
  "ru_pay": false,
  "auto_revenue_view": false,
  "special_offer": false
}
```

Этот JSON нельзя копировать поверх действующего Dashboard: уже подключённый RU
Billing сохраняет product-решение владельца. Release не имеет app-default
`ru_pay = true` и принимает положительное разрешение только из
`.verifiedFreshRemote`.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Documentation/Assets/README/remote-config-cache-flow-dark.svg">
  <source media="(prefers-color-scheme: light)" srcset="Documentation/Assets/README/remote-config-cache-flow-light.svg">
  <img alt="Разные права provider payload и platform cache для special_offer и ru_pay" src="Documentation/Assets/README/remote-config-cache-flow-light.svg" width="100%">
</picture>

| Provenance | Обычный paywall | `special_offer` | `ru_pay` |
|---|---:|---:|---:|
| Текущий Adapty payload: network или SDK cache | да | по своему `true` | нет без fresh proof |
| Dashboard fallback, зарегистрированный через SDK | да | по своему `true` | нет |
| Host-controlled verified-fresh remote | да | по своему `true` | по `true` |
| Persistent cache BroadMonetization | да | нет | нет |

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
`24:00:00 → 00:00:00 → 24:00:00`; ноль не скрывает offer и не блокирует
purchase.

<table>
  <tr>
    <td align="center" width="50%">
      <img src="Documentation/Assets/README/References/special-offer-step-1-paywall.png" alt="Обычный subscription paywall" width="100%">
      <br><strong>1. Subscription paywall</strong>
      <br><sub>Close без confirmed purchase/restore</sub>
    </td>
    <td align="center" width="50%">
      <img src="Documentation/Assets/README/References/special-offer-step-2-offer.png" alt="Второй paywall Special Offer" width="100%">
      <br><strong>2. Special Offer</strong>
      <br><sub>Только после resolver и explicit gate</sub>
    </td>
  </tr>
</table>

Скриншоты показывают **последовательность**, а не обязательный дизайн. Тексты,
изображения, продукты, таймер и скидка остаются app-owned.

## RU Billing

RU methods показываются, только если одновременно выполнены все условия:

1. host app зарегистрировал RU Billing adapters;
2. verified-fresh provider payload содержит `ru_pay = true`;
3. регион iPhone — `RU/RUS` **или** первый preferred language — Russian;
4. RU catalog не пуст и точно сопоставлен выбранному product;
5. backend authorization/kill switch разрешает checkout;
6. entitlement не подтверждает уже активный premium.

SDK cache, Dashboard fallback и persistent cache BroadMonetization не
авторизуют СБП/карту. Возврат из внешней формы не является success: он запускает
backend reconciliation, а неопределённый результат остаётся `pending`.

## Token purchases и recovery

<p align="center">
  <img src="Documentation/Assets/README/References/5115-token-paywall-dark.png" alt="Reference token paywall с несколькими consumable packages" width="46%">
</p>

Token paywall использует отдельный `TokenPurchaseManager`. Количество packages
не фиксировано: 0 даёт empty state, 1…N показываются в provider order. Этот
reference демонстрирует устойчивость списка; его тексты, цены и product IDs не
являются стандартом платформы.

```text
purchase evidence → unique operation ID → exactly-once backend fulfillment
login/reinstall   → current app account → full balance snapshot
```

StoreKit `Restore` не восстанавливает consumable balance. Transaction/checkout
ID нужен backend для deduplication начисления, но не передаётся как вход
обычного recovery. Local cache не является источником купленного доступа или
баланса.

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
