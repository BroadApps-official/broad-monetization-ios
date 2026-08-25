# Changelog

Все заметные изменения BroadMonetization фиксируются здесь с объяснением: что изменилось и почему.

## Unreleased

### Changed

- README восстановил актуальные operational guides из последней полной
  platform-инструкции: Adapty paywall/placement baseline, Remote Config
  provenance, Special Offer, RU Billing, token purchases и recovery;
- app UI screenshots теперь помечены как reference поведения, а не готовый
  дизайн или hardcoded catalog;
- устаревшая umbrella-installation и зависимость от private monolith не
  перенесены.

### Почему

После федерации repository хорошо описывал API, но потерял важную product и
financial context. Новый README снова отвечает на частые вопросы рядом с кодом,
не ослабляя fail-closed authority и не публикуя app-owned secrets/IDs.

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
