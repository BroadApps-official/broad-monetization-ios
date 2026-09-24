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
  <img alt="Release 5.0.0" src="https://img.shields.io/badge/release-5.0.0-10B981">
</p>

Provider-neutral monetization-модуль BroadApps для paywall catalog,
Adapty/StoreKit adapters, entitlements, purchase/restore coordination, Special
Offer и safe analytics.

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

RU Billing вынесен в отдельный пакет: [настройка кодом и с агентом](Documentation/RUBillingExperiments.md).
Обновление зависимости без нового optional tracker сохраняет прежнее поведение.

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
| `BroadMonetization` | iOS 17+, iPhone | `BroadCore` from `3.0.0` | Adapty `3.17.3`, Swinject `2.10.0` |

Host app подключает этот repository только по надобности. Обязательного
umbrella package нет. Если app напрямую импортирует `BroadCore`, его product
тоже добавляется в app target.

## Installation

```swift
dependencies: [
    .package(
        url: "https://github.com/BroadApps-official/broad-monetization-ios.git",
        from: "5.0.0"
    )
]
```

## Базовая настройка Adapty

RU checkout без отдельного payment-status endpoint поддержан с 3.0.0:
[подключение account policy, подписки и токенов](Documentation/RUAccountPolicy.md).

С **2.0.1 ключи Remote Config читаются из выбранного paywall текущего
плейсмента**. Например, экран из настроек получает ключи paywall в `settings`.
Только отсутствующие ключи берутся из текущего paywall `main`. Явные `false`,
`null` и некорректные значения текущего placement не заменяются fallback.
Это правило распространяется на `ru_pay`, `auto_revenue_view`, `special_offer`
и display/navigation metadata. Aliases одного ключа разрешаются вместе.
Пара `experiment_code` / `segment_code` берётся целиком из одного источника:
неполная пара текущего placement отключает отчёт, а не смешивает A/B-варианты.

Продукты, порядок и дубли, `variationID`, SDK references и аналитика показа
принадлежат загруженному placement. При недоступном обычном paywall используется
`main`; продукты `tokens` и `special_offer` им не подменяются. Запрос `main`
ради недостающих настроек не регистрирует показ. Если `main` недоступен,
настройки текущего placement продолжают работать. Полученный запрет сохраняется
при ошибке загрузки продуктов. Gate и A/B-коды не восстанавливаются из кеша.

Для token placement адаптер сначала пробует настроенный ID, а при отсутствии
paywall — альтернативное написание `token` / `tokens`. Настроенный регистр
пробуется первым, затем известные варианты в нижнем регистре. Произвольные
custom ID не угадываются. Оба написания исключены из подписочного fallback.

Custom repositories передают конфигурацию своего placement с fallback
недостающих полей на `main` и честный provenance. Стандартный Adapty SDK
по-прежнему не доказывает свежесть RU gate; требования authority сохраняются.

Реальные keys, product IDs и placement IDs принадлежат host app. Модуль хранит
typed contract и fallback policy, но не вшивает строки конкретного проекта.

Для обычного anonymous-приложения базовая настройка состоит из public SDK key и
placement mapping:

```swift
let adapty = AdaptyPlatformConfiguration(apiKey: appConfiguration.adaptyPublicKey)!
let placements = AdaptyPlacementRegistry(
    main: AdaptyPlacementID(rawValue: appConfiguration.mainPlacement),
    mappings: [
        .tokens: AdaptyPlacementID(rawValue: appConfiguration.tokensPlacement),
        .specialOffer: AdaptyPlacementID(rawValue: appConfiguration.specialOfferPlacement)
    ]
)

let factory = AdaptyMonetizationFactory(
    configuration: adapty,
    placementRegistry: placements,
    messages: appOwnedMessages
)
```

Access level и собственный `AdaptyIdentityProviderProtocol` для этого маршрута
не нужны. Они остаются advanced API только для приложения с собственной
signed-in identity или отдельным authoritative entitlement adapter.

| Что настраивается | Базовое правило для нового app |
|---|---|
| Product без trial | Командная naming convention — суффикс `nottrial` слитно, например `weekly_9.99_nottrial`; runtime на имя не полагается |
| Paywall names | `main`; опциональные `tokens` и `special_offer` только когда flow действительно нужен |
| Placement IDs | `onboarding`, `pro_icon`, `settings`, `main`, `CTR`, `special_offer`; дополнительные — из app specification |
| Fallback | Обычные подписочные placements используют `main`; `tokens` и `special_offer` исключены. Фактический fallback фиксируется в payload context |
| Products | `getPaywall → getPaywallProducts → 1:1 mapping → raw registry`; без filter/sort/dedup |

Пример payload для **нового приложения с выключенным Special Offer**:

```json
{
  "special_offer": false
}
```

Этот JSON нельзя копировать поверх действующего Dashboard: реальный payload и
его остальные поля принадлежат конкретному приложению.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Documentation/Assets/README/remote-config-cache-flow-dark.svg">
  <source media="(prefers-color-scheme: light)" srcset="Documentation/Assets/README/remote-config-cache-flow-light.svg">
  <img alt="Public SDK key и placement проходят через Adapty в полный paywall payload" src="Documentation/Assets/README/remote-config-cache-flow-light.svg" width="100%">
</picture>

## Special Offer: где теперь стоит gate

Претензия «блок идёт до парсинга подписок» закрыта явным pipeline:

```text
Adapty.getPaywall
  → Adapty.getPaywallProducts
  → mapping всего provider array без filter/sort/dedup
  → storage exact raw-product references
  → special_offer = true из Remote Config основного paywall
  → products из отдельного Special Offer placement
```

`ResolveSpecialOfferUseCase` сначала загружает основной paywall и после
парсинга его products читает strict boolean `special_offer`. При `true`
резолвер проверяет persisted cadence и только затем загружает отдельный
placement Special Offer со всеми его products. Fallback на `main` не может
подменить оффер.

Цикл фиксирован: 24 часа окна показа, затем 24 часа cooldown.
Countdown идёт до конца текущего окна и на нуле истекает; UI закрывает
экран. Cooldown начинается точно от границы окна, даже если приложение
в этот момент не запущено. Flag off, confirmed purchase и restore
сбрасывают persisted cycle.

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
изображения, число карточек и скидка остаются app-owned; цикл таймера задаёт
платформа.

## RU Billing

RU logic, HTTP adapters, callbacks, polling and payment UI now belong to the optional
[BroadRUBilling repository](https://github.com/BroadApps-official/broad-ru-billing-ios).
Do not add it to applications that only use App Store billing.
Use `AppleCheckoutMethodsUseCase` and `CheckoutSelectedProductUseCase(applePurchase:)`
for the base composition. See [5.0 migration](Documentation/OptionalProviders.md).

## Повтор Apple-покупки

`PurchaseSelectedProductUseCase` хранит intent до известного результата
StoreKit. Отмена пользователем и окончательный отказ StoreKit без успешной
транзакции очищают intent: после освобождения operation gate кнопку можно
нажать снова.
`AdaptyPurchaseRepository` различает эти исходы по типизированным кодам
Adapty/StoreKit, включая `StoreKitError` из StoreKit 2 и вложенный `SKError`
из `productPurchaseFailed`. Текст ошибки и `AppError.isRetryable` сами по себе
не дают права очистить intent. В частности, после ошибки сети или неизвестного
системного сбоя запись остаётся: платформа не знает, прошла ли оплата.

После успешного ответа Adapty платформа сначала сохраняет этап
`transactionConfirmed`, затем проверяет свежий entitlement. Если проверка
временно недоступна, запуск или возврат в приложение повторит её без поиска
той же покупки по времени в истории StoreKit. Для отложенной оплаты, сетевой
ошибки и неопределённого ответа это правило не действует: нужна verified
StoreKit transaction для точного SKU.

Если premium выдаётся через `StoreKitAppleEntitlementVerifier`, передайте в
`AdaptyMonetizationFactory.makeServices(..., premiumProductCatalog:)` тот же
`ApplePremiumProductCatalog`, что передан entitlement source. Тогда SKU или
тип продукта, появившийся в удалённом Adapty paywall без поддержки в каталоге
доступа, будет отклонён **до** `makePurchase`. Paywall при этом сохраняет
порядок и состав продуктов от Adapty; недоступный товар не скрывается молча.

При отложенной оплате, сетевой ошибке или неопределённом ответе intent остаётся.
Повторный `makePurchase` в этом состоянии запрещён: host должен показывать
ожидание и вызывать `PendingApplePurchaseCoordinator.applicationDidBecomeActive()`
при запуске, возврате в приложение и пока открыт заблокированный paywall.
Только verified StoreKit transaction с точным product ID и подтверждённый
entitlement завершают восстановление. Нельзя очищать intent по таймауту,
отсутствию транзакции в одном опросе или нажатию «попробовать ещё раз».
Intent, сохранённый старой версией как `outcomeUnknown`, не становится
отменённой покупкой после обновления SDK: без verified transaction он требует
разбора поддержкой.

### Диагностика незавершённой Apple-покупки

`PendingApplePurchaseStore.diagnosticSnapshot()` и
`PendingTokenPurchaseStore.diagnosticSnapshot()` возвращают
`PendingPurchaseDiagnostic`. Его `supportText` можно вставить в письмо или
форму поддержки. Там есть ID попытки, product/placement/variation, время
начала и последней проверки, этап и безопасный диагностический код. Чек,
подписанная транзакция, баланс и ID пользователя туда не попадают.

Платформа сохраняет этот общий контекст в локальном Keychain без iCloud sync.
После переустановки он может остаться, даже если локальная запись о покупке
исчезла; тогда `isPendingLocally == false`, а этап `localRecordMissing`.
Это повод сверить покупку, а не доказательство оплаты и не разрешение повторно
списать деньги. Если Keychain недоступен, активный intent всё равно даёт
снимок из основного хранилища, но без последней проверки.

Для подписки `reviewRequired` становится `true` через 24 часа ожидания.
Это только признак для обращения в поддержку: он не снимает блокировку,
не отменяет покупку и не запускает восстановление сам по себе. Проверку
начисления токенов после переустановки host реализует для своего backend;
платформа не владеет его балансом или webhook.

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

Начиная с 4.0.1 verified JWS consumable-покупки передаётся в token flow прямо
из результата Adapty/StoreKit и сохраняется до backend fulfillment. Поэтому
корректность не зависит от `Transaction.all`: на iOS 17 завершённый Adapty
consumable там отсутствует. `AppleTransactionUpdatesBridge`, установленный до
старта Adapty, тем же способом принимает Ask-to-Buy и другие out-of-band
завершения; короткий process-local буфер не теряет событие, если
`TokenPurchaseManager` создаётся чуть позже. `Transaction.unfinished`, затем
`Transaction.all` остаются recovery fallback. Буфер bridge живёт только в
процессе: если приложение завершилось до сохранения JWS, завершённый consumable
по умолчанию исчезает из `Transaction.all`. Host с idempotent ledger по Apple
transaction ID может включить `SKIncludeConsumableInAppPurchaseHistory` в
Info.plist для восстановления и после такого прерывания. Backend обязан
различать уже начисленные transaction ID, иначе повторная выдача токенов опасна.

Pending intent сохраняется при `.pending`, `.unavailable` и `.failed` независимо
от `AppError.isRetryable`. Повтор использует то же evidence и attempt ID без
нового provider purchase. Только `.rejected(error)` явно подтверждает окончательный
отказ backend и очищает store, освобождая общий operation gate. Ошибка очистки
оставляет блокировку. Host не должен очищать pending по кнопке или таймауту.

Не переводите временную ошибку, ожидание webhook, сбой авторизации или исправимое
сопоставление продукта в `.rejected`. Если transaction уже начислена текущему
аккаунту, верните `.alreadyCredited(balance)`. Для миграции на 4.0.0 обновите
exhaustive switches по `TokenFulfillmentOutcome`; существующие adapters с
`.failed(error)` сохраняют прежнее восстановление.

Не определяйте `.credited` по росту общего баланса после вызова `fulfill`:
webhook может прийти до первого чтения, а баланс может вырасти по другой причине.
Backend adapter должен проверять именно `request.evidence.transactionID` и
возвращать `.credited`/`.alreadyCredited` по результату атомарного учёта этой
транзакции.

Уже зависшие попытки, созданные версией 4.0.0 на iOS 17 после auto-finish,
могут не иметь локально доступного JWS. Их нельзя безопасно очищать по таймауту:
сверьте transaction на backend через App Store Server API/notifications или
данные провайдера, выполните идемпотентное начисление и только затем очистите
конкретный pending attempt.

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
bash Scripts/check_token_purchase_contracts.sh
```

Проверки компилируют production types и фиксируют order/provenance,
product identity, Special Offer countdown и provider authority без
XCTest/Swift Testing.

## Sandbox

```bash
bash Scripts/generate_sandbox.sh
open Examples/BroadMonetizationSandbox/BroadMonetizationSandbox.xcodeproj
```

Sandbox показывает fixture products, parsed remote flags, Special Offer/provider
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
