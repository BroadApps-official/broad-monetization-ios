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
  `unavailable`; ответ есть, но условие не выполнено — внутренний `pending`.
  Координатор завершает локальное ожидание и возвращает `waitingCompleted`.

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

С 5.0.0 после ограниченного polling координатор сохраняет последнюю попытку как
`PendingRUCheckoutState.awaitingReconciliation` и освобождает общий operation
gate. `RUPaymentReturnOutcome.waitingCompleted` означает «за время ожидания оплата
не подтверждена»: UI убирает spinner и позволяет снова купить. Это не `inactive`,
не отмена и не доказательство истечения ссылки. При ошибке проверки возвращается
`unavailable`, но локальное ожидание также завершается, если удалось сохранить
изменение для той же сессии и попытки. Ошибка хранилища или смена identity не
разрешает обход блокировки; UI перечитывает gate, а не разблокирует кнопки вслепую.

Повторная проверка/foreground только сверяет последнюю попытку с аккаунтом.
Новая покупка начинается исключительно по нажатию пользователя и атомарно
заменяет попытку с завершённым ожиданием. Перед созданием checkout перечитывается
свежая account policy: активная подписка запрещает ещё один subscription checkout,
для токенов берётся новый исходный баланс. При недоступном backend новая ссылка
не создаётся. Ответ старого polling не может удалить или разблокировать новую
попытку. Старые persisted records без признака завершённого ожидания проходят
обычный polling; cache TTL не снимает блокировку.

Предыдущие попытки после замены не опрашиваются отдельно. Поздние оплаты видны
через обычное восстановление подписки и баланса аккаунта. Рост баланса означает
только новое состояние аккаунта, не атрибуцию конкретной оплаты; host заменяет
баланс полученным значением, не начисляет пакет повторно. Две действующие ссылки
всё ещё могут быть оплачены: дедупликация и срок жизни ссылок принадлежат backend.

Начиная с 4.1.0 host может передать в `RUBillingCompositionDependencies`
`checkoutTerminationClient`. Его свежий авторизованный backend-вызов
должен атомарно отменить checkout либо доказать терминальный `failed`,
`cancelled` или `expired`. После явного подтверждения пользователя вызывайте:

```swift
let outcome = await services.checkout.pendingCheckoutTermination
    .terminatePendingCheckout()
```

Этот client опционален и не требуется для завершения локального ожидания.
Только `.terminated(status)` доказывает серверное завершение и удаляет ровно
сохранённые `checkoutSessionID` и `attemptID`. `.pending`, `.unavailable` и
отсутствующий client не меняют существующее состояние ожидания.
Не вызывайте termination автоматически при `sceneDidBecomeActive`
или закрытии web view: пользователь мог продолжить оплату в банковском
приложении. Сначала спросите, действительно ли он хочет отменить попытку.

Backend adapter не должен выводить terminal status из device time или локального
`expiresAt`. В BroadApps account-policy checkout ID может быть локальной
корреляцией. Adapter должен надёжно связать запрос с нужной backend-попыткой:
некоррелированная команда «отменить текущий checkout» может затронуть новую
покупку и не подходит. `.terminated` допустим только после серверной гарантии,
что именно эта попытка больше не может завершиться оплатой. Повтор с теми же
`checkoutSessionID` и `attemptID` должен быть идемпотентным.

В режиме с authoritative `paymentStatus` неопределённый статус по-прежнему
блокирует новые операции до подтверждения оплаты или terminal status.

Смена режима не делает старый pending совместимым: сначала завершите его прежним
способом; context без account expectation никогда не превращается в успех.

## Переход с 2.x

`paymentStatus` теперь optional. В exhaustive switch по `RUPaymentReturnOutcome`
и `RUPaymentRefreshOutcome` добавьте `.tokensCredited`. Именно эти изменения
публичного контракта требуют major 3.0.0; сценарий с указанным status endpoint
сохраняет прежнее поведение.

## Переход с 4.x на 5.0.0

В exhaustive switch добавьте `RUPaymentReturnOutcome.waitingCompleted` и
`PendingRUCheckoutState.awaitingReconciliation`. Custom pending stores должны
реализовать `finishWaiting` через durable compare-and-replace; default
implementation возвращает false и сохраняет блокировку. Новый enum case и
изменение retry-поведения требуют major release. `checkoutTerminationClient`
больше не является обязательным условием account-policy integration.

Проверка: `bash Scripts/check_ru_account_policy_contracts.sh` и полный
`bash Scripts/module_gate.sh`. Реальные платежи и unit/UI tests не запускаются.
