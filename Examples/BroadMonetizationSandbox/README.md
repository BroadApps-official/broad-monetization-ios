# BroadMonetizationSandbox

## Проверка общего Remote Config (2.0.0)

Sandbox использует typed fixtures. Для проверки загрузчика выполните
`bash Scripts/check_ru_experiment_contracts.sh` из корня: исполняемый контракт
передаёт противоположные флаги в `main` и другие placements, проверяет пять
общих ключей, порядок и дубли продуктов, отсутствие ответа и обновление config.
Custom repositories передают config `main` с каждым payload, включая оффер.

RU A/B fixture section demonstrates optional metadata and its removal for
unqualified provider cache. No tracker networking is started by this sandbox.
Executable selection/reporting scenarios run through the module gate;
[production wiring](../../Documentation/RUBillingExperiments.md) uses the existing
RU composition. Legacy initializers remain valid without the optional tracker.

Fixture-only iPhone app для проверки products-first pipeline, Special Offer
provenance/countdown и отдельной verified-fresh RU authority.

```bash
bash Scripts/generate_sandbox.sh
open Examples/BroadMonetizationSandbox/BroadMonetizationSandbox.xcodeproj
```

Sandbox не содержит real keys/IDs и не активирует SDK, purchase, restore
или RU payment.
