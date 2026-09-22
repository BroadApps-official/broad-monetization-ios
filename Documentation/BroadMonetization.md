# BroadMonetization guide

BroadMonetization изолирует financial/remote-feature domain от готового UI и
app-owned product decisions.

## Paywall catalog

Adapty adapter сначала получает paywall, затем весь products array.
Mapping сохраняет provider order, duplicate SKU occurrences, commercial
fingerprint и exact raw-product reference.

Обычный anonymous-host настраивает public SDK key и `AdaptyPlacementRegistry`.
Access level и custom identity provider не входят в базовую загрузку paywall.
Независимо от placement модуль передаёт UI все 0…N products без
filter/sort/dedup.

## Product price presentation

`ProductPricePresenter` считает по массиву продуктов производные цифры, которых
не отдаёт ни один provider: цену, приведённую к одной неделе, процент экономии
относительно самого дорогого недельного тарифа и один best-value бейдж.
Результат — `ProductPricePresentation` с полями `weeklyPrice: Money?`,
`savingsPercent: Int?` и `isBestValue: Bool`.

Всё fail-closed: продукт без декодированного `Money` или с периодом, который
нельзя привести к неделям (`custom`/`unknown`), просто теряет эти цифры вместо
угаданного значения. Процент экономии сравнивается только между продуктами в
одной валюте: суммы в USD, RUB и других валютах никогда не сопоставляются как
обычные числа. Модуль возвращает только числа; локализованное форматирование
остаётся presentation-задачей BroadUIFlows. Массив продуктов не фильтруется, не
сортируется и не дедуплицируется, порядок сохраняется.

```swift
let presenter = ProductPricePresenter()
let rows = presenter.presentations(for: payload.products)
```

Конвертацию месяцев и лет в недели можно настроить через
`ProductPricePresenter.PeriodWeights`.

## Special Offer

Основной paywall владеет strict boolean gate, а отдельный placement
владеет продуктами:

```text
main Remote Config: special_offer == true
        ↓
persisted окно 24 часа / cooldown 24 часа
        ↓
separate Special Offer placement: все products без filter/sort/dedup
```

Fallback на main не может подменить offer placement. Countdown идёт до
конца текущего окна, на нуле истекает и закрывает UI. Cooldown начинается
точно от `expiresAt`. Flag off, confirmed purchase и restore сбрасывают цикл.

## Special Offer: compatibility API кампании

`ResolveSpecialOfferCampaignUseCase` сохранён для source compatibility,
но больше не задаёт параллельный контракт. Он тоже читает strict boolean
`special_offer` из Remote Config основного paywall. Только exact `true`
разрешает загрузку отдельного offer placement; `false`, отсутствие и
неверный тип закрывают показ и сбрасывают цикл. Fallback не может
подменить ни main, ни offer.

Кадэнс фиксирован платформой: сутки оффера, потом тихие сутки
(`SpecialOfferCadence`), и считается он по **серверному времени**
(`ServerTimeProviderProtocol` из BroadCore). Часы передаются в резолвер
**параметром без значения по умолчанию** — хост, забывший их отдать, не
соберётся, а не окажется молча на часах устройства. Пока сервер не ответил,
оффер не показывается.

Активная подписка отсекается **до** любых обращений к пейволу, кэшу и сети:
платящему нечего продавать со скидкой. Это относится и к подписочному экрану,
который приложение может открыть подписчику само (например из управления
подпиской): экран откроется, оффера после него не будет.

Покупка и восстановление не прячут оффер, а гасят окно, поэтому следующая
кампания начинается с полных суток, а не доживает остаток прежней.

Когда спрашивать, тоже решает платформа. `SpecialOfferCampaignCoordinator`
слушает события, которые пейвол и так шлёт, и после каждого закрытия без покупки
публикует решение в `decisions`. Свой экран он не преследует, за покупкой и
восстановлением — гасит окно. Приложение подписывается один раз и только рисует.

```swift
let configuration = SpecialOfferCampaignConfiguration(placementID: .specialOffer)
let coordinator = SpecialOfferCampaignCoordinator(
    resolve: ResolveSpecialOfferCampaignUseCase(
        configuration: configuration,
        loadPaywallUseCase: services.loadPaywall,
        windowRepository: PersistedSpecialOfferWindowStore(store: keyValueStore),
        presentationLifecycle: services.paywallPresentationLifecycle,
        entitlementStatusProvider: entitlementEngine,
        serverTime: serverClock
    ),
    configuration: configuration,
    followedPlacementIDs: [.main]
)
await relay.connect(coordinator)          // relay обёрнут вокруг аналитики хоста

for await decision in coordinator.decisions {
    guard case let .campaign(campaign) = decision else { continue }
    present(campaign.placementID, remaining: campaign.remainingTimeInterval)
}
```

Кампания несёт плейсмент, а не payload: экран грузит плейсмент сам, поэтому
презентация, которую он рисует, принадлежит ему. Презентацию, на которой
принималось решение, резолвер закрывает сам.

## Debug: локальная покупка

`LocalStoreKitPurchaseRepository` и `LocalStoreKitRestoreRepository` (только под
`#if DEBUG`) проводят покупку/восстановление через локальный `.storekit` конфиг,
подключённый к схеме, вместо боевого провайдера. Пейвол и каталог не меняются —
меняется только касса: debug-сборка завершает покупку без денег и без receipt
validation. Доступ здесь **не** выдаётся: транзакция настоящая, а премиум
подтверждает тот же боевой entitlement-путь (`StoreKitAppleEntitlementVerifier`
против премиум-каталога). Это прод-идентичный тест, а не обход. Локальный конфиг
подставляется при запуске из Xcode; в Release эти типы не компилируются.

## RU Billing

RU services and their UI moved to the optional [BroadRUBilling package](https://github.com/BroadApps-official/broad-ru-billing-ios). See [5.0 migration](OptionalProviders.md) for provider composition and durable state compatibility.

## Entitlements and recovery

Premium access вычисляется из authoritative sources. Cache даёт
bounded fallback, но не подменяет server verification. Recovery и token
fulfillment остаются idempotent app/backend boundaries.

`AppleTransactionUpdatesBridge` — единственный `Transaction.updates` листенер:
ставится один раз до старта Adapty и не вызывает `finish()`. Premium-факты он
форвардит в `PendingApplePurchaseCoordinator`, а verified JWS consumable-покупок —
в текущий `TokenPurchaseManager`. Короткий process-local буфер сохраняет событие,
если manager создаётся после bridge. Обычный успешный token checkout получает тот
же JWS прямо из результата Adapty до того, как auto-finish скроет transaction из
истории iOS 17. `Transaction.unfinished` и `Transaction.all` используются только
как recovery fallback. Так не теряются и покупки, завершившиеся вне приложения.
Раньше этот listener писал каждый host.

Для диагностики (например, письмо в поддержку) `EntitlementStatus.supportSubscriptionValue`
даёт канонический строковый статус (`subscribed`/`not_subscribed`/`unknown`), а
`ProfileIdentityProviderProtocol` (реализация `AdaptySDKProfileIdentityProvider`)
читает текущий Adapty profile ID — без создания нового профиля, `nil` если SDK ещё
не активирован. Host сам подставляет свой placeholder вместо `nil`.

## Проверка

```bash
bash Scripts/module_gate.sh
```
