# Спешл оффер RU Billing

Сначала полностью подключите обычный RU Billing по разделу
[README](../README.md#ru-billing): catalog, `ru_pay`, регион, checkout,
reconciliation и подтверждение Premium. Ниже описаны только отличия Special
Offer.

`BroadMonetization` не создаёт второй платёжный движок для coupon flow. Он
использует существующие RU catalog, exact product mapping, checkout и
entitlement reconciliation.

## Граница модуля

Модуль уже предоставляет:

- `RUCatalogProductKind.coupon`;
- `RUCatalogSections.coupons` с сохранением backend order и duplicates;
- `ResolveRUCatalogProductUseCase` и `RUCatalogProductMatcher` для exact ID;
- общий RU checkout и pending reconciliation;
- strict `ru_pay` + Storefront/region gate.

Host app предоставляет:

- текущий provider payload с единственным gate `special_offer = true`;
- app-owned catalog configuration и authorization;
- coupon product ID или decoder подтверждённого legacy marker;
- optional Apple placement;
- SwiftUI и copy.

## Рекомендуемый catalog contract

```json
{
  "products": [
    {
      "productId": "premium_offer_month_ru",
      "appStoreProductId": "premium_offer_month",
      "title": "Premium по специальной цене",
      "kind": "coupon",
      "period": "month",
      "price": 799,
      "currency": "RUB",
      "paymentMethods": ["sbp", "card"]
    }
  ]
}
```

```swift
let sections = RUCatalogSections(catalog: payload)
let offers = sections.coupons // весь массив, backend order сохранён
```

Если нужен один offer, host передаёт его exact case-sensitive ID. Модуль не
выбирает продукт по цене, периоду, позиции или «лучшему» ranking.

Legacy backend может обозначать coupon полем вроде `widgetTitle = kupon`.
Такое поле преобразует небольшой app-owned
`RUCatalogResponseDecoderProtocol`; универсальный decoder не должен угадывать
смысл произвольной строки.

## Gate и результат покупки

```text
special_offer == true
AND coupon exact-match найден
AND verified-fresh ru_pay = true
AND (Storefront RU OR регион iPhone RU)
→ показать СБП/карту
```

`special_offer = true` всегда показывает сам экран Special Offer. Любое другое
значение не показывает его. Остальные строки не являются условиями показа
экрана: они определяют только наличие RU-способов оплаты и точного продукта.

Apple-вариант может остаться доступным независимо от RU gate. Возврат из
внешней формы создаёт только pending: Premium открывается после нового
authoritative entitlement/backend result `active`.

## Таймер

Таймер — локальная визуализация с одним жёстким циклом:

```text
24:00:00 → 00:00:00 → 24:00:00 → …
```

Цикл запускается при первом показе и продолжается между следующими открытиями,
поэтому через час остаётся примерно `23:00:00`. Он не запрашивает серверное
время, не является сроком действия и не меняет решение Remote Config. На нуле
экран и покупка остаются доступны, а отсчёт сразу начинает новый круг.

Полная инструкция разработчику и prompt для агента:
[публичная документация](https://broadapps-ios-docs.nkhsnv.chatgpt.site/docs/ru-special-offer).
