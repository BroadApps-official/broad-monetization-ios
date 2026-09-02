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
угаданного значения. Модуль возвращает только числа; локализованное
форматирование остаётся presentation-задачей BroadUIFlows. Массив продуктов не
фильтруется, не сортируется и не дедуплицируется, порядок сохраняется.

```swift
let presenter = ProductPricePresenter()
let rows = presenter.presentations(for: payload.products)
```

Конвертацию месяцев и лет в недели можно настроить через
`ProductPricePresenter.PeriodWeights`.

## Special Offer

Кампания читается из фактически загруженного `PaywallPayload`. Семантика флага —
absence=on: оффер активен, пока провайдер явно не прислал `special_offer=false`.
Резолвер требует свой непустой пейвол, разрешённый именно этим placement
(fallback/подменённый main отклоняется).

Два режима `ResolveSpecialOfferUseCase`:

- **Untimed** (preferred init) — оффер показывается, пока грузится разрешённый
  собственный пейвол; окно/часы не консультируются, countdown визуально зациклен.
- **Timed** (init с `stateRepository:` + `clock:`) — включает кадэнс «сутки через
  сутки». Резолвер берёт доверенное серверное время из `SpecialOfferClock`, ведёт
  окно через `SpecialOfferStateRepositoryProtocol` и отдаёт `.active(SpecialOfferWindow)`
  (показ на каждом закрытии в течение окна) с реальным countdown, затем
  `.cooldown(until:)`; без доверенного времени — `.untrustedTime` (fail-closed).
  Длительности берутся из конфигурации или дефолтов 24ч
  (`defaultWindowDuration`/`defaultCooldownDuration`).

Доверенные часы даёт `ServerSynchronizedSpecialOfferClock`: host скармливает ему
серверный `Date` из заголовка ответов backend (`HTTPServerDate.date(from:)`), а
`makeSpecialOfferClock()` отдаёт готовый `SpecialOfferClock` для timed-инициализатора.
Offset персистится, high-water монотонный (откат назад запрещён).

Сборка timed-оффера:

```swift
let clock = ServerSynchronizedSpecialOfferClock(store: keyValueStore)
// из HTTP-слоя приложения: await clock.record(HTTPServerDate.date(from: response) ?? Date())
let resolve = ResolveSpecialOfferUseCase(
    loadPaywallUseCase: loadPaywall,
    stateRepository: PersistedSpecialOfferStateRepository(store: keyValueStore),
    presentationLifecycle: lifecycle,
    clock: clock.makeSpecialOfferClock()
)
```

Резолвер отдаёт `SpecialOfferResolution` с `presentationAuthorization`; его
`countdown` уже несёт реальный остаток окна, и `BroadSpecialOfferMetadataView`
(BroadUIFlows) показывает его без доработок. **Оркестрацию** — *когда* показать
второй пейвол (обычно при закрытии первого без покупки) и когда его скрыть на
нуле — ведёт приложение: маршрут презентации у каждого приложения свой.

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

Coupon-flow использует тот же catalog и checkout. `RUCatalogProductKind.coupon`
и `RUCatalogSections.coupons` сохраняют весь backend-массив. Host передаёт
campaign gate, exact coupon ID, optional Apple placement и отдельные
eligibility/countdown policies. Отдельный target, скрытый product ranking и
второй entitlement engine не нужны.

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

Для диагностики (например, письмо в поддержку) `EntitlementStatus.supportSubscriptionValue`
даёт канонический строковый статус (`subscribed`/`not_subscribed`/`unknown`), а
`ProfileIdentityProviderProtocol` (реализация `AdaptySDKProfileIdentityProvider`)
читает текущий Adapty profile ID — без создания нового профиля, `nil` если SDK ещё
не активирован. Host сам подставляет свой placeholder вместо `nil`.

## Проверка

```bash
bash Scripts/module_gate.sh
```
