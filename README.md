# WindShipOpt.jl

Design optimisation of wind-assisted coasters for long ocean routes. It compares a conventional VLSFO coaster with diesel-electric e-methanol coasters with no rig, rigid wings or a towing kite, with weather routing on every voyage. The figure of merit is the cost per tonne-kilometre of the transport service.

## Model chain

1. **Hull**: Holtrop–Mennen (1984) calm-water resistance, with Kijima side-force slope and slender-body induced drag for leeway.
2. **Rig**: rigid wings via a lifting-line polar with trim optimised per wind; kite via a quasi-steady crosswind model without reeling, with pattern-centre azimuth optimised per wind; both limited by heel and leeway.
3. **Propulsion**: actuator-disk propeller with a viscous loss factor; engines or gensets with a part-load efficiency curve.
4. **Performance table**: fuel power over (speed, 10 m wind, true wind angle), per design.
5. **Routing**: forward dynamic programming over (stage, lateral node, arrival time) in a corridor, minimising fuel cost plus time cost.
6. **Economics**: capital annuity, crew, maintenance, port calls and cargo interest; the time cost per hour makes the per-voyage optimum the per-tonne-km optimum.

Every number the model assumes, with its sensitivity range and the reason for it, is in [`data/assumptions.yaml`](data/assumptions.yaml).

## Running

```bash
cp Manifest-v1.12.toml.default Manifest-v1.12.toml
juliaserver launch .
juliaserver run . scripts/compare_designs.jl -o
```

## Status

Milestone 1 runs end to end on synthetic weather. Not yet in the model: ERA5 wind (ARCO-ERA5), waves (SNNM added resistance), currents, a real coastline, batteries with regeneration, kite polars calibrated with SymbolicAWEModels, rudder drag, forecast-limited routing, and an outer design optimiser.
