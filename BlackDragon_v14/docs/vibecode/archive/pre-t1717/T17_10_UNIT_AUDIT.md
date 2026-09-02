# T17.10 Point / Pip / Tick Deep Audit

Baseline: HEAD `1ac8d3fd0080dd6a5ed1cf48b2dc5d43aba6d9f0`, tree `5779e104f00656f3444116a3ce44f13fc7dff8b8`.

## Quantitative domains

| Domain | Canonical internal unit | Boundary |
|---|---|---|
| TP/SL/trailing/spread/slippage inputs | price | `Config_BindUnitProfile` |
| DCA chain | price | `CDistancePlan.DistancePrice` |
| Recovery/Core/Hedge Pyramid `*Pips*` | price or integer ticks | `Unit_PipSizePure` through compatibility wrappers |
| Broker deviation | broker points | `Exec_DeviationFromPrice` immediately before request |
| Stops/freeze level | broker points converted to price | broker metadata boundary only |
| Cash/economic reserve | money | price / tick-size * tick-value * lots |
| Volume | broker volume units | existing volume-step floor/ceil helpers |
| Percentage | percent | no distance conversion |

## Findings and disposition

| ID | Severity | Finding | Disposition |
|---|---:|---|---|
| U-01 | P1 | `DistanceSequence_` used fixed `10` reference points per pip; FX 4-digit became 10x too wide. | Fixed in opt-in `PIP_UNIFIED`; exact historical bridge retained in default `LEGACY_COMPAT`. |
| U-02 | P1 | Basket cost shift paired tick value with `_Point`; wrong when tick-size differs from point. | Fixed: `Unit_CostShiftPricePure` pairs tick value with tick size. |
| U-03 | P1 | Legacy TP/SL/trailing and Pips-suffixed Recovery/Pyramid values had ambiguous 10x meaning. | Fixed by explicit versioned mode; no silent `.set` reinterpretation. |
| U-04 | P1 | AutoGoldPip OFF could make common legacy distances disagree with true-pip Recovery/Pyramid. | Unified mode ignores AutoGoldPip and uses symbol pip; legacy preserves old behavior. |
| U-05 | P1 | Slippage conversion was duplicated in opens, closes and economic reserves. | Fixed: canonical slippage price; broker-point conversion only in ExecutionLayer. |
| U-06 | P1 | Unit policy was absent from Recovery persistence identity. | Fixed conditionally: unified policy revision invalidates incompatible active state; default legacy fingerprint stays byte-compatible. |
| U-07 | P1 | Missing point/tick metadata could silently produce zero conversions. | Fixed: OnInit fails closed when point, tick-size, pip or legacy reference size is invalid. |

## Legitimate broker-native math retained

- `SYMBOL_SPREAD * _Point` is a broker-point-to-price conversion, not pip math.
- `max(SYMBOL_TRADE_STOPS_LEVEL, SYMBOL_TRADE_FREEZE_LEVEL) * _Point` is required by MetaTrader broker contracts.
- Recovery settlement tolerances use `max(tick-size, point)` deliberately; they are identity/fill tolerances, not user distance inputs.
- All tick-value consumers were checked; each receives or reads a positive tick-size before price/cash conversion.

## Migration truth table

| Symbol profile | Legacy TP_=300 | Unified TP_=300 | Legacy DCA=20 | Unified DCA=20 |
|---|---:|---:|---:|---:|
| XAU 3-digit (`point=.001`, `pip=.10`) | 3.00 | 30.00 | 2.00 | 2.00 |
| XAU 2-digit (`point=.01`, `pip=.10`) | 3.00 | 30.00 | 2.00 | 2.00 |
| EURUSD 5-digit (`point=.00001`, `pip=.00010`) | .00300 | .03000 | .00200 | .00200 |
| EURUSD 4-digit (`point=.00010`, `pip=.00010`) | .03000 | .03000 | .02000 | .00200 |

The FX 4-digit DCA difference is the proven historical defect. It is corrected only after explicit unified-mode opt-in.

## Verification status

- Independent T17.10 C++ truth model: 36/0 PASS locally.
- All C++ model regression: 30 suites, zero failures locally.
- Focused source invariants: PASS locally.
- VibeCodeKit lint/deep review: executed; release remains blocked without native compile and Strategy Tester evidence. Generic AP-20 hits on broker point boundaries were manually classified above.
- MetaEditor/native/full exact-head regression: pending GitHub Windows workflows.
- Strategy Tester/broker parity/forward: UNTESTABLE until owner evidence.
