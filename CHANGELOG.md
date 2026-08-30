# Changelog

Все заметные изменения BroadMonetization фиксируются здесь с объяснением: что изменилось и почему.

## Unreleased

### Added

- базовый `AdaptyPlatformConfiguration(apiKey:)` без обязательного access level;
- `AdaptyAnonymousIdentityProvider` и короткий initializer
  `AdaptyMonetizationFactory` для стандартного anonymous-приложения;
- `FlatRUCatalogResponseDecoder` и
  `RUBillingWireAdapters.broadAppsFlatCatalog(supportedMethods:)` для текущего
  плоского backend catalog без app-specific копирования decoder.

### Changed

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
- RU Special Offer закреплён как coupon-секция существующего каталога и
  checkout: campaign/timers остаются app-owned, product выбирается только по
  exact ID, browser return требует authoritative entitlement result; отдельные
  targets и второй payment engine не добавлены.

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
