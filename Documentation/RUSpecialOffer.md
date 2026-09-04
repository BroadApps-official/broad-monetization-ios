# RU Billing: Special Offer

RU Billing не меняет экран, gate или цикл обычного Special Offer.
Он меняет только источник RU-продукта и маршрут оплаты.

## Канонический backend contract

Backend каталог возвращает полный массив. Special Offer отмечается
strict boolean полем `isSpecialOffer` (также поддерживается
`is_special_offer`):

```json
{
  "products": [
    {
      "productId": "premium_offer_month_ru",
      "appStoreProductId": "premium_offer_month_ru",
      "kind": "subscription",
      "period": "month",
      "price": 799,
      "currency": "RUB",
      "paymentMethods": ["sbp", "card"],
      "isSpecialOffer": true
    }
  ]
}
```

Правила:

- обычный paywall не использует строку с `isSpecialOffer = true`;
- `ResolveRUSpecialOfferProductUseCase` возвращает её только при одном
  однозначно помеченном продукте;
- checkout resolution дополнительно требует exact case-sensitive ID
  выбранного Adapty product;
- если marker отсутствует, неоднозначен или ID не совпал, обычный
  тариф не подставляется;
- UI получает `price`, `currency` и display price из этой backend-строки;
- checkout получает её точный `productId`.

## Показ и время

Gate берётся из Remote Config основного paywall. При strict boolean
`special_offer = true` действует общий цикл: 24 часа окна, 24 часа
cooldown. Countdown истекает на нуле. Выключение flag, confirmed purchase
и restore сбрасывают persisted cycle.

## Подтверждение Premium

Возврат из browser не является оплатой. Premium открывается только
после authoritative backend/RU Billing status `active`.

RU Billing A/B-тесты общей платформой пока не поддержаны.
