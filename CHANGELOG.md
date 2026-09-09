# Changelog

Все заметные изменения BroadMonetization фиксируются здесь с объяснением: что изменилось и почему.

## 1.5.4

### Fixed

- The opt-in RU loader selects all default subscriptions when Adapty is
  unavailable, returns no products, or has no exact backend ID matches.
  It reuses the existing exact IDs → isDefault → complete subscription section
  policy; legacy catalogs without defaults remain usable.
- Any exact match keeps the complete provider payload and SDK handles. A live
  nonempty provider catalog requires the existing fresh RU gate before backend
  selection. Received prohibitions and dedicated placement exclusions remain.
- Backend cards retain their original catalog indices and full commercial
  fingerprints after default selection, including duplicate IDs with different
  prices. Checkout never substitutes an unrelated Apple product or offer.
- Regression probes cover defaults, partial matches, legacy catalogs, gate
  provenance and fresh checkout identity. Public signatures are unchanged.
  SemVer intent: compatibility patch for the opt-in reserve path.

## 1.5.3

### Fixed

- A successful Adapty response with an empty product array now triggers the
  opt-in fresh RU backend catalog, just like a product loading failure, when
  either the Storefront or device region is Russian. Received false, missing
  or invalid ru_pay still prohibits the reserve path.
- Added empty-response checks across regional combinations, main/ordinary
  placements and dedicated token/Special Offer exclusions. Existing public
  APIs and the normal loader are unchanged. SemVer intent: compatibility patch.

## 1.5.2

### Fixed

- Token and Special Offer placements never fall back to main or to the ordinary
  RU subscription catalog. Their own products, prices and payment flow stay
  isolated; ordinary subscription placements retain main fallback.
- Executable checks cover both the original loader and the opt-in RU loader
  with an available main paywall. Public signatures are unchanged.
  SemVer intent: corrective patch for dedicated placement isolation.

## 1.5.1

### Fixed

- An unconfigured optional placement still falls back to main first. If the
  configured main provider is unavailable, the opt-in RU backend loader can
  continue; only a missing main mapping is a composition error that closes it.
  Received false/invalid/absent configurations continue to prohibit fallback.
- Added executable optional-placement/main composition cases. Public APIs are
  unchanged. SemVer intent: compatibility patch for the 1.5 fallback path.

## 1.5.0

### Added

- Opt-in `LoadPaywallWithRUFallbackUseCase`, `RUBillingCompositionFactory.makePaywallLoader`
  and `AdaptyMonetizationFactory.makeServicesWithRUFallback`: a Russian Storefront
  or device region may load the configured backend catalog when Adapty/products
  are unavailable. Existing factory signatures and default loading are unchanged.
- Attempt-scoped provider evidence preserves received false/invalid/absent flags
  even when StoreKit products fail. No response is distinct from an absent field.
- Fresh backend selection preserves row order, duplicates and commercial terms;
  RU-only products never offer Apple checkout. Before checkout, a fresh catalog
  must still contain the exact selected occurrence with unchanged terms.
- Ephemeral fallback authorization cannot survive JSON/cache or activate Special
  Offer/experiment reporting. Backend payment/entitlement authority is unchanged.
- Executable regional/response, selection, serialization and cancellation probes,
  compile-only sandbox wiring, DocC and upgrade documentation.
  SemVer intent: additive minor release with explicit host opt-in.

## 1.4.1

### Fixed

- Restored exact pre-1.4 initializer overloads as delegating compatibility
  shims. Existing apps can keep typed references to factory, catalog, remote
  configuration and key-registry initializers as well as ordinary calls.
  Default parameters alone do not preserve an initializer's function type.
- Added compile-only references for every restored signature; RU A/B behavior
  and the optional 1.4 API are unchanged. SemVer intent: compatibility patch.

## 1.4.0

### Added

- Opt-in RU Billing A/B reporting: strict current experiment/segment metadata,
  shared authenticated assign → paywall-shown transport and one attempt per
  presentation. Failed assignment never fabricates a shown segment; a stored
  backend segment is reported without changing the Adapty variant.
- `RUBillingCompositionFactory.makeExperimentTracker` and optional
  `AdaptyMonetizationFactory.ruBillingExperiments` integrate the existing show
  lifecycle without blocking dismissal or changing checkout.
- `RUCatalogProduct.isDefault` and explicit `RUExperimentCatalogSelector` support
  exact matches → defaults → complete section while preserving the original
  backend array, order, duplicate rows and Special Offer boundaries.
- Executable compatibility/concurrency/HTTP probes, sandbox examples and
  manual/agent integration guide. SemVer intent: additive minor; existing
  initializers and JSON remain valid, reporting defaults to disabled.

## 1.3.1

### Documentation

- Public source documentation for `PersistedSpecialOfferStateRepository`
  now states its actual role in the canonical 24-hour window/cooldown contract.

## 1.3.0

### Changed

- Standard Special Offer приведён к контракту Марии: strict boolean gate
  читается из основного paywall, а все products загружаются из
  отдельного offer placement без fallback-подмены.
- Восстановлен фиксированный цикл 24 часа показа / 24 часа cooldown.
  Countdown истекает на нуле; flag off, confirmed purchase и restore
  сбрасывают persisted cycle.
- RU catalog сохраняет strict `isSpecialOffer`; обычный paywall исключает
  помеченные строки, а Special Offer требует marker и exact ID. RU price,
  currency и `productId` сохраняются до checkout.
- Campaign-shaped compatibility API больше не обходит контракт:
  он тоже читает gate из main, требует доверенное время и
  использует фиксированный цикл 24/24.
- Default aliases `coupon`/`kupon` и string/number coercion для Special Offer gate
  удалены: default key — только `special_offer`, custom exact key по-прежнему
  передаётся через `RemoteConfigKeyRegistry`.

### Added

- `SpecialOfferCoordinator` и `SpecialOfferAnalyticsRelay` для перехода после
  закрытия обычного paywall и автоматического сброса цикла по
  confirmed purchase/restore.
- `ResolveRUSpecialOfferProductUseCase` и marker-aware checkout resolution.

## 1.2.0

### Added

- Параллельный путь Special Offer «по наличию кампании»: `ResolveSpecialOfferCampaignUseCase`
  показывает оффер, когда плейсмент ответил своим пейволом со свежим payload и
  непустым каталогом. Ключ `special_offer` в этом режиме не требуется — явный
  `false` остаётся kill switch, отсутствие ключа нейтрально. Живые кампании в
  кабинете флага рядом с собой не несут, поэтому флаговый резолвер их не видел.
  Существующий `ResolveSpecialOfferUseCase` не изменён: проект выбирает путь в
  композиции.
- `SpecialOfferCadence` — правило «сутки оффера, потом тихие сутки» отдельной
  арифметикой, и `PersistedSpecialOfferWindowStore`, который хранит
  под него одну отметку через `KeyValueStoreProtocol`. Длительности из
  remote config перекрывают дефолты.
- Кадэнс считается по серверному времени: резолвер принимает
  `ServerTimeProviderProtocol` **без значения по умолчанию**, а `timePolicy` по
  умолчанию отказывается показывать оффер, пока бэкенд не подтвердил время.
  Окно нельзя растянуть переводом часов устройства.
- `SpecialOfferCampaignCoordinator` и `SpecialOfferCampaignAnalyticsRelay` —
  платформа сама решает, когда спрашивать: оффер идёт следом за пейволом,
  закрытым без покупки, не преследует собственный экран и гасит окно на покупке
  или восстановлении. Активная подписка отсекается до обращений к пейволу, кэшу
  и сети.

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
