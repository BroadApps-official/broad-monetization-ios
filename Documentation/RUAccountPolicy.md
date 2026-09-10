# Подтверждение RU-оплаты через состояние аккаунта

С 3.0.0 отдельный endpoint статуса платежа необязателен. Если backend после
web checkout обновляет подписку и баланс в `GET /v1/policy/effective`,
используйте account-policy режим. Старый режим с `paymentStatus` остаётся.

## Подключение

В `RUBillingEndpointConfiguration` не передавайте `paymentStatus` (либо задайте
`nil`), а `entitlementStatus` направьте на `/v1/policy/effective`.
`RUBillingCompositionFactory` автоматически выберет account-policy polling,
flat catalog и `BroadAppsAccountPolicyWireContract` для checkout/entitlements.
Для другого wire-контракта передайте свои adapters; для существующего API-клиента
можно передать `dependencies.accountPolicyRepository`. Этот repository обязан
делать свежий авторизованный запрос для переданного subject, без cache fallback.
Cancellation остаётся отдельным контрактом: передайте свои cancellation adapters,
если backend использует другой запрос/ответ. Новый режим не меняет отмену подписки.

[Компилируемый пример](../Examples/BroadMonetizationSandbox/Sources/RUAccountPolicyWiringExample.swift).

## Что проверяется

После закрытия встроенной payment page и после перехода приложения в active
вызывайте один и тот же `services.checkout.applicationReturn.applicationDidBecomeActive()`.
Координатор объединяет одновременные вызовы. Polling по умолчанию — до 8 запросов
с паузой 2 секунды **между** попытками; на успехе останавливается раньше.
`RUPaymentPollingPolicy` позволяет изменить лимит. Закрытие страницы само по себе
не подтверждает оплату.

- Подписка: свежий `isSubscribed == true` и непустой `plan`, совпадающий с
  выбранным backend product ID без учёта регистра или с его периодом.
  Поддержаны day/daily, week, month, year/annual в строке плана. Период из
  выбранной строки каталога приоритетнее вывода из ID. Это проверка результата,
  она не меняет точное сопоставление товаров в каталоге.
- Токены: свежий `creditsBalance` больше баланса **до создания checkout**.
  Исходный баланс запрашивается до оплаты и сохраняется в subject-scoped pending
  context. Retry и восстановление context не меняют это значение.
- Ошибка, чужой subject или смена сессии не дают успеха. Нет свежего ответа —
  `unavailable`; ответ есть, но условие не выполнено — `pending`.

Для подписки платформа дополнительно обновляет общий entitlement и возвращает
`.active(snapshot)` только после свежего подтверждения backend authority.
Токены возвращаются отдельно: `.tokensCredited(balance)`, без выдачи premium и
без локального прибавления купленного пакета. Host применяет полученный баланс.

## Маршрут токенов

Используйте `services.catalog.resolveTokenCheckoutMethods` и
`services.checkout.startSelectedToken`. Они принимают выбранный consumable,
проверяют точное соответствие строке tokens в backend-каталоге, RU gate, consent
и общий operation gate. Нет свежего исходного баланса — checkout не создаётся.
`startSelectedProduct` остаётся маршрутом подписки; `TokenPurchaseManager`
обрабатывает Apple-покупку. В собственном экране токенов маршрутизируйте Apple
в этот manager, а SBP/card — в `startSelectedToken`.

## Pending и смысл подтверждения

Этот режим подтверждает состояние аккаунта, а не конкретную транзакцию.
Уже активный такой же тариф или рост баланса из другого источника тоже могут
выполнить условие. Если backend должен доказать оплату именно этого checkout,
используйте режим с `paymentStatus`.

После 8 попыток pending остаётся: можно закрыть paywall, показать понятное
сообщение и предложить повторную проверку. Retry вызывает только reconciliation,
не создаёт новый checkout. Pending блокирует новую финансовую операцию до
подтверждения; истечение времени или закрытие страницы не доказывает отмену
платежа. Для гарантированного завершения отменённых checkout нужен достоверный
terminal status backend. Смена режима не делает старый pending совместимым:
сначала завершите его прежним способом; context без account expectation
никогда не превращается в успех.

## Переход с 2.x

`paymentStatus` теперь optional. В exhaustive switch по `RUPaymentReturnOutcome`
и `RUPaymentRefreshOutcome` добавьте `.tokensCredited`. Именно эти изменения
публичного контракта требуют major 3.0.0; сценарий с указанным status endpoint
сохраняет прежнее поведение.

Проверка: `bash Scripts/check_ru_account_policy_contracts.sh` и полный
`bash Scripts/module_gate.sh`. Реальные платежи и unit/UI tests не запускаются.
