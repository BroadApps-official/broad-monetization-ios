# Contributor guide

## Boundary

BroadMonetization может зависеть только от compatible `BroadCore` и явно
declared vendor SDKs. `BroadUIFlows`/`BroadExtensions` запрещены. Domain не
импортирует Adapty, StoreKit, UIKit или SwiftUI.

## Layout

```text
Sources/BroadMonetization/Domain          provider-neutral models/protocols
Sources/BroadMonetization/Application     use cases, gates, DI
Sources/BroadMonetization/Data            repositories/cache coordination
Sources/BroadMonetization/Infrastructure  Adapty/StoreKit/RU/backend adapters
Examples/BroadMonetizationSandbox         fixture-only iPhone example
Scripts/ContractProbes                    executable non-test probes
```

## Invariants

- Provider product array не filter/sort/dedup; occurrence identity уникальна.
- Special Offer gate выполняется после paywall + all-products mapping.
- Provider-managed payload может разрешить Special Offer; platform cache нет.
- RU Billing требует verified-fresh remote authority и explicit `ru_pay = true`.
- Timeout/offline не превращают pending operation в success/failure и не повторяют charge.
- Cache не авторизует entitlement, purchase или remote feature.
- Raw URL/error/receipt/token/user/payment data не логируются.

## Public API

Additive API — minor, compatible fix — patch, breaking API/behavior — major.

```bash
bash Scripts/generate_public_api_report.sh --update
```

## Contract probes

Probe компилирует production sources и возвращает nonzero при нарушении.
XCTest/Swift Testing и `Tests/` не добавляются.

## Release

Release notes отвечают: **Что изменилось и почему?**

1. Обновите changelog/docs/sandbox/API report.
2. Пройдите clean `bash Scripts/module_gate.sh`.
3. Создайте tag `x.y.z` и дождитесь release workflow.
4. Обновите compatible range в `BroadUIFlows`.
5. Соберите exact combination в integration repository.
6. После PASS обновите compatibility catalog и public docs.
