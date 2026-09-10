# BroadMonetization agent rules

- Меняйте только этот repository.
- Модуль может импортировать `BroadCore`, но не `BroadUIFlows`/`BroadExtensions`.
- Domain не импортирует UI, Adapty, StoreKit и другие vendor SDK frameworks.
- Не filter/sort/dedup provider products и не воссоздавайте raw product из SKU.
- Remote Config читается из выбранного paywall текущего placement;
  main — fallback только для отсутствующих ключей. Явные false/invalid/null
  текущего placement не заменяются main. Продукты и SDK references остаются
  у своего placement; запрет сохраняется при ошибке продуктов.
- Token placement пробует настроенный ID и известные token/tokens aliases;
  ни одно написание не допускает подмены подписочным main или RU-каталогом.
- Special Offer gate выполняется после paywall/products parsing.
- Standard Special Offer читает strict boolean gate из выбранного
  paywall gatePlacementID с fallback ключей на `main`, загружает все products из отдельного placement и не
  подставляет main fallback.
- Standard Special Offer имеет фиксированный цикл: 24 часа окна,
  24 часа cooldown; countdown истекает на нуле, а flag off,
  confirmed purchase и restore сбрасывают persisted cycle.
- RU Special Offer выбирает backend row только по `isSpecialOffer`;
  обычный paywall не использует эту строку.
- RU Billing/entitlements/purchase/recovery сохраняют fail-closed authority.
- Не добавляйте `Tests/`, test targets, XCTest, Swift Testing или UI tests.
- Не добавляйте secrets, real IDs и raw error/URL/receipt/token/user/payment data.
- Public API меняется вместе с DocC, sandbox, report, changelog и SemVer intent.
- Перед сдачей выполните `bash Scripts/module_gate.sh` и не заявляйте PASS иначе.
