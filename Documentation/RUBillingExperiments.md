# RU Billing A/B: подключение к платформе

Доступно в BroadMonetization **1.4.0**. Это эксперименты оплаты через RU backend.
Вариант по-прежнему назначает Adapty; backend связывает показ с RU-платежом
по текущему авторизованному пользователю. Нового распределения пользователей
в платформе нет.

## Обновление существующего приложения

Обновление зависимости само по себе ничего не включает. Оба initializer
`AdaptyMonetizationFactory` получили последний optional-параметр
`ruBillingExperiments = nil`. Без него остаётся прежний lifecycle Adapty,
запросов эксперимента нет. Старые initializer каталога работают без `isDefault`,
старый JSON декодируется с `isDefault = false`. Зависимости на Adapty 3.17.3
и остальные модули не изменены.

Если приложение уже отправляет `assign`/`paywall-shown`, оставьте его путь
до отдельного переключения. При включении платформенного tracker уберите
именно старую отправку и ручной `Adapty.logShowPaywall` из этой ветки.
Два tracker или два независимых lifecycle дадут двойной учёт.

## Что подготовить

1. Работающий RU Billing: HTTP configuration, текущие subject, authorization
   provider и session binding должны быть теми же, что у checkout.
2. Варианты и продукты placement в Adapty; matching `experiment_code` и
   `segment_code` в Remote Config и backend. Оба кода — строки длиной 1–64,
   без окружающих пробелов и управляющих символов. Числа/bool не приводятся к строке.
3. `ru_pay = true` из текущего подтверждённо свежего payload и регион iPhone
   RU/RUS **или** текущий Storefront RU/RUS. Кэш не восстанавливает разрешение
   и старые коды эксперимента.
4. Подтверждённые backend endpoints. `.broadApps` задаёт пути
   `/v1/billing/cloudpayments/experiments/assign` и
   `/v1/billing/cloudpayments/experiments/paywall-shown` относительно вашего
   существующего `http.baseURL`. Другие пути передаются явно.

**Свежесть уже является требованием RU Billing платформы.** Стандартный
Adapty 3.17.3 adapter помечает payload как `providerCacheFallbackPossible`:
успешный SDK callback сам по себе не доказывает свежесть Remote Config.
В таком приложении добавление tracker не откроет RU-ветку. Сохраните существующий
проверенный источник `.verifiedFreshRemote`; если его нет, сначала согласуйте
контракт проверки свежести. Не переименовывайте cache в fresh и не включайте
Debug override в Release ради A/B-теста.

## Подключить кодом

В composition root используйте **существующие** RU factory, Adapty identity,
configuration, registry, context и messages. Имена переменных ниже обозначают
объекты приложения, а не готовые credentials или endpoints.

```swift
let experiments = ruFactory.makeExperimentTracker(configuration: .broadApps)

let adaptyFactory = AdaptyMonetizationFactory(
    configuration: adaptyConfiguration,
    identityProvider: identityProvider,
    placementRegistry: placementRegistry,
    messages: messages,
    context: adaptyContext,
    ruBillingExperiments: experiments
)
```

Дальше создавайте services прежним `makeServices`. Готовые экраны BroadUIFlows
и собственный UI через `TrackPaywallEventUseCase` используют этот lifecycle.
Он резервирует один показ по `presentationID` и запускает отчёт в фоне:
ошибка или медленный backend не задерживает крестик, переключение продуктов,
закрытие и checkout. Отчёт начинается при фактическом появлении, не при prefetch.
Resolved placement переводится через `AdaptyPlacementRegistry` в dashboard ID;
при fallback учитывается placement, который действительно дал paywall.

Для полностью собственного lifecycle доступен
`await experiments.trackShown(paywall, placement: actualDashboardPlacement)`.
Вызовите его один раз из события появления; при `.useAdapty` выполните свой
обычный Adapty show. Для остальных outcomes Adapty show не вызывается.
Закрытие завершайте `await experiments.presentationDidEnd(paywall.presentationID)`.
Каждое новое открытие получает новый `presentationID`; повторные callbacks
одного открытия присоединяются к одной попытке. Не подключайте оба способа сразу.

Один tracker принадлежит одному RU composition и одному session binding.
При logout инвалидируйте общую `SubjectAuthorizationSession`; для нового
аккаунта создайте новый binding и composition, как при обычной RU-оплате.

## Выбрать продукты RU-варианта

Это отдельное явное действие в host UI, которое показывает backend-каталог.
Платформа продолжает возвращать весь каталог. Существующие готовые Adapty
экраны сохраняют provider array и exact-ID checkout; автоматически превращать
backend-строки в фиктивные Adapty products нельзя.

```swift
let selection = RUExperimentCatalogSelector().select(
    productIDs: paywall.products.map(\.productID),
    in: fullBackendCatalog,
    kind: .subscriptions
)
// Передайте selection.products существующему RU UI.
// Сохраните fullBackendCatalog для остальных экранов.
```

| Ситуация | Результат |
|---|---|
| Есть точные совпадения `catalogProductID` или `appStoreProductID` | Все совпавшие строки в порядке backend, включая дубли |
| Совпадений нет | Все `isDefault = true` нужного раздела |
| Совпадений и defaults нет | Весь нужный раздел, как до подключения |
| Часть ID отсутствует | Совпавшие строки + `missingProductIDs` для диагностики |
| `.specialOffer` | Только подписки с `isSpecialOffer = true`, включая fallback |
| `.tokens` | Только обычные token-строки; офферные строки исключены |

`source` показывает причину выбора. Поле `isDefault` не означает выбранный
радиобаттон и не переопределяет default product Adapty. Flat и BroadApps decoders
принимают `isDefault`, `default`, `is_default`; отсутствующий/неверный тип даёт false.
Цена, валюта, supported methods и checkout ID остаются из backend-строки.

## Как считается показ

При открытом RU-gate и корректных кодах отправляется `assign`, затем
`paywall-shown`. Оба тела содержат только `experimentCode`, `segmentCode`,
`placement`; пользователь определяется существующим Bearer credential.

`paywall-shown.segmentCode` всегда берётся из успешного `assign.segment.code`.
При `requestedSegmentMatches = false` экран остаётся вариантом Adapty,
а outcome `.reported(requestedSegmentMatches: false)` сигнализирует о расхождении.
Приложение не переключает UI на backend-сегмент.

Ошибка назначения не вызывает `paywall-shown` с запрошенным кодом. Неуспешный
RU-отчёт не отправляется в Adapty вместо backend. Автоматических retry нет:
backend endpoint показа не обещает идемпотентность. Новая попытка — при следующем
фактическом открытии. Потерянный ответ не позволяет гарантировать exactly-once
на сервере; здесь защищены повторные клиентские callbacks одного открытия.

`onOutcome` возвращает типизированный результат без токенов, user ID, payload
и raw errors. В Release логируйте только разрешённые категории. Смена аккаунта
между запросами останавливает дальнейший отчёт старого composition.

## Подключить с агентом

Кодовый и агентский пути используют один API. Агент выполняет интеграцию
небольшими изменениями; новый backend или дизайн от него не требуется.

```text
Добавь opt-in RU Billing A/B из BroadMonetization 1.4.0 в существующее приложение.
Сначала прочитай Documentation/RUBillingExperiments.md модуля и текущий
AppIntegrationPlan. Зафиксируй текущие RU-gate/freshness, JWT session binding,
показ Adapty, backend endpoints, matching ID и существующие A/B callbacks.
Не придумывай отсутствующий backend-контракт: отметь BLOCKED и вынеси
конкретный вопрос на backend contract review по правилам host repository.
После принятия этого этапа подключи один tracker к текущему composition.
Отдельно подключи selector только к существующему backend RU UI, сохраняя
исходный каталог. Удали заменённые дубли отправки; остальную оплату сохрани.
Проверь выключенную конфигурацию, старый каталог без isDefault, варианты,
ошибки assign/shown, fallback placement, reopen и logout во время assign.
Проведи функциональную и визуальную проверку по staged workflow приложения.
```

## Проверка модуля

`bash Scripts/check_ru_experiment_contracts.sh` компилирует реальные domain,
parser, selector, tracker и HTTP adapter и выполняет fixture-сценарии.
HTTP перехвачен локальным URLProtocol; платежей и внешних запросов нет.
Полный release gate — `bash Scripts/module_gate.sh`, включая public API,
iPhone Simulator, unsigned generic iOS и DocC.

Семантика внешних API: [Adapty A/B tests](https://adapty.io/docs/ab-tests).
В этом release остаётся Adapty SDK 3.17.3; миграция SDK не входит в подключение A/B.
