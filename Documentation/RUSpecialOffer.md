# Спешл оффер RU Billing

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

- campaign/experiment decision;
- app-owned catalog configuration и authorization;
- coupon product ID или decoder подтверждённого legacy marker;
- optional Apple placement;
- eligibility-window и visual-countdown policy;
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
campaign разрешён
AND coupon exact-match найден
AND verified-fresh ru_pay = true
AND (Storefront RU OR регион iPhone RU)
→ показать СБП/карту
```

Apple-вариант может остаться доступным независимо от RU gate. Возврат из
внешней формы создаёт только pending: Premium открывается после нового
authoritative entitlement/backend result `active`.

## Таймеры

Модуль не назначает RU Special Offer общий таймер. Persistent eligibility и
визуальный countdown — разные app-owned policy. Их значения передаёт владелец
задачи текущего приложения.

Полная инструкция разработчику и prompt для агента:
[публичная документация](https://broadapps-ios-docs.nkhsnv.chatgpt.site/docs/ru-special-offer).
