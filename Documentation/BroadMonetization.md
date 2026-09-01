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

`special_offer = true` читается из фактически загруженного payload только после
получения полного `PaywallPayload`. Duration/cooldown — legacy metadata, а
24-часовой countdown — recurring visual timer, не eligibility boundary.
Расписание, trusted clock и динамическая длительность не входят в текущий
contract.

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

## Проверка

```bash
bash Scripts/module_gate.sh
```
