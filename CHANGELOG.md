# Changelog

## Unreleased

### Added

- `WindShipOpt.cycle_wear_cost(rig, assumptions)`: what one kite launch and landing wears out of the kite, the part of `cycle_cost` beyond crew and turn.

### Changed

- BREAKING: `ShipDesign` no longer takes `kite_aspect_ratio`; a design's kite flies the aspect ratio of the assumption `kite_aspect_ratio`, which `with_value` or `with_kite_aspect_ratio` changes. `WindShipOpt.kite_aspect_ratio(design, assumptions)` is gone with it.
- BREAKING: `form_factor`, `return_corridor`, `jonswap` and `added_resistance` are no longer exported; call them as `WindShipOpt.<name>`.
- `with_changed` refuses a change naming a field the object does not have.
