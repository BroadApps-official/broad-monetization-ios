# BroadMonetization guide

BroadMonetization изолирует financial/remote-feature domain от готового UI и
app-owned product decisions.

## Paywall catalog

Adapty adapter сначала получает paywall, затем весь products array.
Mapping сохраняет provider order, duplicate SKU occurrences, commercial
fingerprint и exact raw-product reference.

## Special Offer

`special_offer = true` и dedicated provenance проверяются только после
получения полного `PaywallPayload`. Duration/cooldown — legacy metadata, а
24-часовой countdown — recurring visual timer, не eligibility boundary.

## RU Billing

RU path разрешён только при host opt-in, explicit valid `ru_pay = true`,
verified-fresh remote payload, Russian device context и доступных backend
methods. Debug override по умолчанию locked.

## Entitlements and recovery

Premium access вычисляется из authoritative sources. Cache даёт
bounded fallback, но не подменяет server verification. Recovery и token
fulfillment остаются idempotent app/backend boundaries.

## Проверка

```bash
bash Scripts/module_gate.sh
```
