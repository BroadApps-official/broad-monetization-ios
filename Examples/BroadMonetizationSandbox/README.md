# BroadMonetizationSandbox

## Проверка Remote Config текущего placement (2.0.1)

Sandbox использует typed fixtures. Для проверки загрузчика выполните
`bash Scripts/check_ru_experiment_contracts.sh` из корня: исполняемый контракт
передаёт противоположные флаги в `main` и другие placements, проверяет приоритет
текущего paywall, fallback отсутствующих ключей, false/null/invalid, aliases,
целостность A/B-пары, порядок и дубли продуктов, отсутствие ответа и refresh.
Отдельно проверяются token/tokens: настроенный ID первым, остановка на успехе,
отсутствие подписочного fallback и сохранение произвольных custom ID.
Custom repositories передают config текущего placement с fallback на main.

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
