# BroadMonetization agent rules

- Меняйте только этот repository.
- Модуль может импортировать `BroadCore`, но не `BroadUIFlows`/`BroadExtensions`.
- Domain не импортирует UI, Adapty, StoreKit и другие vendor SDK frameworks.
- Не filter/sort/dedup provider products и не воссоздавайте raw product из SKU.
- Special Offer gate выполняется после paywall/products parsing.
- RU Billing/entitlements/purchase/recovery сохраняют fail-closed authority.
- Не добавляйте `Tests/`, test targets, XCTest, Swift Testing или UI tests.
- Не добавляйте secrets, real IDs и raw error/URL/receipt/token/user/payment data.
- Public API меняется вместе с DocC, sandbox, report, changelog и SemVer intent.
- Перед сдачей выполните `bash Scripts/module_gate.sh` и не заявляйте PASS иначе.
