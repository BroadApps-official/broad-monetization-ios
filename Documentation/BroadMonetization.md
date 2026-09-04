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

Кампания читается из фактически загруженного `PaywallPayload`. Решение всегда
сводится к одной проверке:

```text
special_offer == true → всегда показать Special Offer
всё остальное         → не показывать Special Offer
```

Если provider разрешил configured fallback, резолвер использует
фактически загруженный payload и читает gate из него. Host не
добавляет другой gate.

Countdown не участвует в eligibility. Это локальный визуальный цикл
`24:00:00 → 00:00:00 → 24:00:00`: он запускается при первом показе,
продолжается между следующими открытиями и на нуле сразу начинает новый круг.
Для него не нужны серверное время, дата окончания или ответ backend. Ноль не
скрывает экран и не блокирует покупку.

## Special Offer: кампания по наличию

Второй, параллельный путь. Флаговый резолвер выше не меняется — проект выбирает
один из двух в композиции, и выше этой границы ничего не двигается.

Здесь кампания — это пейвол своего плейсмента. Она есть, когда provider ответил
на плейсмент оффера **своим** пейволом, payload — свежий ответ provider (не
восстановленный из кэша платформы), и в нём есть что купить. Ключ `special_offer`
в этом режиме не нужен: явный `false` остаётся kill switch и выключает кампанию
из дашборда без релиза, а отсутствие ключа нейтрально. Это существенно: живые
кампании в кабинете флага рядом с собой не несут.

Кадэнс держит платформа: сутки оффера, потом тихие сутки
(`SpecialOfferCadence`), и считается он по **серверному времени**
(`ServerTimeProviderProtocol` из BroadCore). Часы передаются в резолвер
**параметром без значения по умолчанию** — хост, забывший их отдать, не
соберётся, а не окажется молча на часах устройства. Пока сервер не ответил,
`timePolicy` по умолчанию отказывается показывать оффер вообще.

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

RU path разрешён только при host opt-in, explicit valid `ru_pay = true`,
verified-fresh remote payload, App Store storefront `RU/RUS` **или** регионе
iPhone `RU/RUS`, exact catalog match и доступных backend methods. Язык
приложения и системный язык не участвуют. Debug override по умолчанию locked.

Перед созданием checkout Storefront и gate проверяются повторно. Возврат из
внешней формы создаёт только pending/reconciliation path; Premium подтверждает
authoritative entitlement source.

### Спешл оффер RU Billing

Coupon-flow добавляется только после полностью работающего обычного RU Billing
и использует тот же catalog и checkout. `RUCatalogProductKind.coupon` и
`RUCatalogSections.coupons` сохраняют весь backend-массив. Единственный gate —
`special_offer = true`; host также передаёт exact coupon ID и optional Apple
placement. Локальный countdown не влияет на показ. Отдельный target, скрытый
product ranking и второй entitlement engine не нужны.

[Полный контракт →](RUSpecialOffer.md)

### Backend catalog

Обычный Adapty paywall передаёт UI весь provider array без filter/sort/dedup.
RU catalog загружается через app-owned HTTPS configuration и authorization
adapter. `FlatRUCatalogResponseDecoder` поддерживает текущий ответ
`{ "products": [...] }`, `productId`/`product_id`, title, kind, period, price,
currency, credits и optional exact App Store ID.

```swift
let wire = RUBillingWireAdapters.broadAppsFlatCatalog(
    supportedMethods: [.sbp, .card]
)
```

Способы оплаты задаются явно, если backend не возвращает их в каталоге. Модуль
не угадывает methods, product mapping или единицы цены. Другой backend contract
подключает собственный `RUCatalogResponseDecoderProtocol`.

## Entitlements and recovery

Premium access вычисляется из authoritative sources. Cache даёт
bounded fallback, но не подменяет server verification. Recovery и token
fulfillment остаются idempotent app/backend boundaries.

`AppleTransactionUpdatesBridge` — единственный `Transaction.updates` листенер:
ставится один раз до старта Adapty и форвардит verified purchase-транзакции своего
bundle в `PendingApplePurchaseCoordinator`, не вызывая `finish()`. Так покупка,
завершившаяся вне приложения, не теряется. Раньше этот listener писал каждый host.

Для диагностики (например, письмо в поддержку) `EntitlementStatus.supportSubscriptionValue`
даёт канонический строковый статус (`subscribed`/`not_subscribed`/`unknown`), а
`ProfileIdentityProviderProtocol` (реализация `AdaptySDKProfileIdentityProvider`)
читает текущий Adapty profile ID — без создания нового профиля, `nil` если SDK ещё
не активирован. Host сам подставляет свой placeholder вместо `nil`.

## Проверка

```bash
bash Scripts/module_gate.sh
```
