# Changelog

Все заметные изменения BroadMonetization фиксируются здесь с объяснением: что изменилось и почему.

## 1.1.0

### Added

- базовый `AdaptyPlatformConfiguration(apiKey:)` без обязательного access level;
- `AdaptyAnonymousIdentityProvider` и короткий initializer
  `AdaptyMonetizationFactory` для стандартного anonymous-приложения;
- `FlatRUCatalogResponseDecoder` и
  `RUBillingWireAdapters.broadAppsFlatCatalog(supportedMethods:)` для текущего
  плоского backend catalog без app-specific копирования decoder.
- `ProductPricePresentation` и `ProductPricePresenter` — производные цифры для
  paywall-строки: цена, приведённая к неделе, процент экономии и best-value
  бейдж. Вычисляются из массива продуктов без filter/sort/dedup и возвращают
  только числа (`Money`/`Int`); экономия сравнивается только внутри одной валюты,
  форматирование остаётся presentation-задачей UI. Раньше каждый host считал это
  сам рядом с кнопкой покупки.
- `LocalStoreKitPurchaseRepository` и `LocalStoreKitRestoreRepository`
  (только `#if DEBUG`) — покупка/восстановление через локальный `.storekit`
  конфиг схемы вместо боевого провайдера. Пейвол и каталог остаются прежними,
  меняется только касса: debug-сборка проводит покупку без денег и без receipt
  validation. Доступ здесь не выдаётся — транзакция настоящая, а премиум
  подтверждает тот же боевой entitlement-путь. Это прод-идентичный debug-путь,
  не bypass. В Release не компилируется. Заменяет самодельный local-purchase
  repository, который debug-сборки писали сами.
- `ProfileIdentityProviderProtocol` + `AdaptySDKProfileIdentityProvider`
  — чтение текущего Adapty profile ID для диагностики (поле письма в поддержку) без
  создания нового профиля; `nil` fail-safe, если SDK не активирован. Плюс
  `EntitlementStatus.supportSubscriptionValue` — канонический строковый статус
  (`subscribed`/`not_subscribed`/`unknown`). Закрывает два поля письма в поддержку,
  которые раньше было нечем заполнить (стояло `unavailable` и ad-hoc строка).

- `AppleTransactionUpdatesBridge` — единственный process-wide листенер
  `Transaction.updates`: форвардит только verified purchase-транзакции своего
  bundle (без revocation/upgrade, под ownership policy) в
  `PendingApplePurchaseCoordinator` и никогда не вызывает `finish()` (это делает
  провайдер покупок). Ставится один раз до старта Adapty, чтобы не потерять
  покупку, завершившуюся вне приложения. Убирает app-side listener.

### Changed

- Special Offer остаётся fail-closed: показ разрешает только явный
  `special_offer=true` из текущего provider payload; `false`, отсутствие и
  невалидное значение оффер не включают. Это единственный gate: при `true`
  Special Offer показывается всегда. Если provider разрешил configured
  fallback, gate читается из фактически загруженного payload без
  дополнительного eligibility-условия.
- верх README теперь ведёт в актуальную cross-module карту создания
  приложения, а monetization-детали остаются рядом с owner-кодом;
- README восстановил актуальные operational guides из последней полной
  platform-инструкции: Adapty paywall/placement baseline, Remote Config
  provenance, Special Offer, RU Billing, token purchases и recovery;
- app UI screenshots теперь помечены как reference поведения, а не готовый
  дизайн или hardcoded catalog;
- устаревшая umbrella-installation и зависимость от private monolith не
  перенесены.
- базовый маршрут Adapty теперь описан как public SDK key + placements; custom
  identity и authoritative entitlement adapters вынесены в advanced path;
- подтверждено, что subscription и token paywall получают весь provider array,
  а Special Offer использует только `special_offer = true` и визуальный
  циклический таймер 24 часа без schedule/server clock;
- RU regional gate теперь использует App Store Storefront `RU/RUS` **или**
  регион iPhone `RU/RUS`; язык больше не включает RU Billing;
- текущий Storefront повторно проверяется непосредственно перед RU checkout;
- RU catalog product сохраняет optional backend title и credits, исходный
  порядок и все occurrences.
- RU Special Offer закреплён как дополнение после базовой интеграции RU Billing:
  экран разрешает только `special_offer = true`, product выбирается по exact ID,
  а локальный countdown `24 → 0 → 24` не зависит от сервера и не управляет
  показом; browser return требует authoritative entitlement result.

### Почему

После федерации repository хорошо описывал API, но потерял важную product и
financial context. Новый README снова отвечает на частые вопросы рядом с кодом,
не ослабляя fail-closed authority и не публикуя app-owned secrets/IDs. Новое
региональное правило синхронизирует платформу с текущим product decision, а
готовый flat decoder убирает повторяющиеся app-owned костыли.

## 1.0.0

### Added

- provider-neutral paywall/products, purchase/restore и analytics contracts;
- Adapty/StoreKit adapters и raw-product identity registry;
- entitlement aggregation, bounded caches и recovery boundaries;
- Special Offer pipeline после products parsing и recurring display countdown;
- fail-closed RU Billing composition, safe networking и pending-state handling;
- standalone sandbox, production-type probes, DocC/API report и reproducible gates.

### Почему

Монетизация вынесена в независимый public repository, чтобы financial
и remote-feature behavior можно было ревьюить/выпускать отдельно от Core
и готового UI.
