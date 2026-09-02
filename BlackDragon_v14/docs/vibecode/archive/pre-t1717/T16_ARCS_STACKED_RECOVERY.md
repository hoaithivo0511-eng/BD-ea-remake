# T16 — ARCS Stacked Recovery

Status: **DRAFT / verification only / DO NOT MERGE**.

Baseline: T15 exact verified HEAD `92810b5e0f63144752b257b805596ed9ef4a9f90`.

## Source-of-truth behavior

Owner canonical example:

1. Core BUY `1.00 @ 4200`.
2. Price `4195`: open SELL Hedge G1 `1.00` when Hedge volume = 100%.
3. Price `4190`: virtual Hedge TP fires; close 50% of **G1 only** = `0.50`.
4. Confirmed realized net cash from that close is the only credit allowed to reduce losing Core.
5. Example `+250 cent` funds `0.25` Core close, leaving Core BUY `0.75`.
6. Retained G1 SELL `0.50 @ 4195` receives net-positive protection (Broker or Virtual SL).
7. ARCS_STACKED immediately opens **G2 = 100% x current Core = 0.75**. Retained G1 is not subtracted.
8. Result: Core BUY `0.75`, G1 locked SELL `0.50`, G2 active SELL `0.75`, total Hedge `1.25`, net exposure SELL `0.50`.

If implementation opens G2 `0.25`, the ARCS oracle fails: that is the legacy coverage-deficit architecture, not the approved stacked architecture.

## New Vietnamese-facing inputs

### 18 — ARCS: KHỐI LƯỢNG HEDGE

- `RecoverySizingPolicy_`
  - `HEDGE_CAN_BANG`: desired aggregate Hedge coverage; backward-compatible policy.
  - `ARCS_XEP_LOP`: every new generation is independently sized from residual Core.
- `HedgeVolumePercent_ = 100.0`
  - New generation units = floor(`Core units * percent / 100`).
  - Values below or above 100% are allowed.
  - No upward rounding. A sub-minimum target is rejected rather than increased.

Examples on a `0.01` volume step:

- Core `0.75`, 80% -> Gnew `0.60`.
- Core `0.75`, 100% -> Gnew `0.75`.
- Core `0.75`, 120% -> Gnew `0.90`.
- Core `0.75`, 33% -> Gnew `0.24` (floor, not `0.25`).

### 19 — ARCS: SL & KHÓA LỢI NHUẬN

- `HedgeSLMode_`
  - `SL_BROKER`: real protective SL is submitted to broker.
  - `SL_VIRTUAL`: the target is durable but not sent as broker SL; EA closes the owned layer when the virtual stop is crossed.

Both modes share the same net-BE / lock-profit / safety-buffer target calculation. Only execution differs.

### 20 — ARCS: GLOBAL SL / CHUYỂN PHA

- `EnableGlobalHedgeSL_`
- `GlobalSLAfterGenerations_`
- `GlobalHedgeSLNetProfitPips_`
- `RecoveryReentryBufferPips_`

The common Global SL must be safe for **every live retained layer**, not merely profitable against aggregate weighted entry.

After the Global Hedge stack is stopped/closed, the direction enters TRANSITION. Adverse continuation beyond the re-entry buffer may start a fresh ARCS generation; a favorable reversal moves to REVERSAL_HOLD rather than blindly re-hedging.

## Architecture decisions

### Layer ownership

One Recovery direction can own N retained `LOCKED` layers plus at most one active generation. Generation is correlated from the existing `BDR|C=...|G=...|B=...|N=...` execution comment and durable state.

### TP scope

`HedgePartialClosePercent_` applies only to the **active generation**. Example: G1 locked `0.50`, G2 active `0.75`, 50% partial target is `0.37` on a `0.01` grid — not `0.62` of aggregate `1.25`.

### Core funding

Only confirmed realized Hedge cash (`profit + swap + commission + fee`) from the active TP-partial window is spendable to close losing Core. Broker-confirmed Core losses consume the ledger. Floating/theoretical Hedge profit is not credit.

### Lock scope

Each retained generation is protected from its own entry/net-BE. An aggregate weighted SL may not be used to claim every layer is positive.

### Intentional over-hedge

In `ARCS_XEP_LOP`, `Total Hedge > Core` is valid. Exit coordination must use generation ownership, not the old `Hedge-Core = excess` rule. Unknown/manual topology mutation is fail-closed; full-side/account-wide emergency flatten remains allowed.

### ReHedgeGapPips_

The T15 `ReHedgeGapPips_` input is retained for exact legacy compatibility. It is **not** the normal ARCS next-generation delay. Normal ARCS opens the next generation immediately after confirmed TP partial -> Core funding -> retained-layer lock. `RecoveryReentryBufferPips_` is the post-Global-SL transition buffer.

## Persistence

ARCS uses a separate persistence schema v3 with:

- sizing policy and `HedgeVolumePercent_` in semantic fingerprint;
- SL execution mode;
- Global-SL/re-entry semantics;
- direction phase and ledger;
- each generation target/open/remaining/TP/lock state;
- Virtual SL and Global SL values;
- tester isolation via `RecoveryTesterResumeState_`.

Mismatched schema/config is rejected; old state is never silently resumed under new semantics.

## Verification gates

Before promotion all must pass on the same exact source tree:

1. Complete legacy/T1-T14 model regression remains green.
2. T16 C++ pure model oracle passes.
3. MetaEditor compiles RunTests, T13 mutation, T14 identity, T16 ARCS, and BlackDragon with 0 errors / 0 warnings.
4. Native MT5: legacy 246/0, T13 mutation 26/0, T14 identity 17/0, plus T16 ARCS native gate.
5. Owner Strategy Tester proves the canonical G1 -> partial -> funded Core -> retained lock -> G2 sequence.
6. Owner tests both `SL_BROKER` and `SL_VIRTUAL`.
7. Owner tests Hedge volume below/at/above 100% and broker min/max/volume-limit boundaries.
8. Owner tests Global SL and transition/re-entry.
9. T15 startup isolation and T14 execution-identity gates remain separately satisfied.

Until owner runtime evidence is available: **NOT BACKTEST_ELIGIBLE / NOT FORWARD_ELIGIBLE / NOT LIVE_ELIGIBLE / DO NOT MERGE**.
