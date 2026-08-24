# Changelog

Все заметные изменения BroadMonetization фиксируются здесь с объяснением: что изменилось и почему.

## Unreleased

Пока нет изменений.

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
