# T16 Owner Strategy Tester Gate

Status: runtime-verification protocol for PR #27. **Do not merge before this gate passes.**

Exact source under test:

- HEAD: `d0b1342bad58bc9392785313928a928ac66cf5bc`
- TREE: `ba1cb57c3c3c95ce671758367c7ad9124bfc1af6`
- `BlackDragon.ex5` SHA256: `e338ee9513d1323f75dce694adbc90ae88cf7a6d843ce1bf51fdaf28ae876acd`

Deterministic precondition already satisfied on this exact tree:

- model/static regression: PASS;
- T16 C++ ARCS oracle: 33/0;
- MetaEditor: 0 errors / 0 warnings;
- native MT5 legacy: 246/0;
- T13 mutation: 26/0;
- T14 execution identity: 17/0;
- T16 ARCS policy: 25/0.

## Gate A — Fresh startup

Use `RecoveryTesterResumeState_=false`.

PASS requires:

1. no stale ARCS state from a previous tester pass;
2. Recovery ACTIVE reaches startup-ready state;
3. normal Core entry/DCA can proceed until Recovery takes ownership;
4. no `RECONCILE_REQUIRED`, corrupt persistence, identity mismatch, or unexplained RecoveryMagic exposure at startup.

FAIL on any startup block that is not intentionally caused by the test.

## Gate B — Canonical stacked cycle

Primary preset: `BlackDragon_T16_ARCS_BROKER_FRESHPASS_XAU_M1.set`.

Required semantic oracle at `HedgeVolumePercent_=100`:

1. Core BUY example = `1.00`.
2. G1 opens SELL `1.00` after Recovery trigger.
3. Virtual Hedge TP is scoped to **G1 only**.
4. 50% partial closes G1 `0.50`.
5. Only confirmed realized net cash from that partial close becomes Core-funding credit.
6. Core losing exposure is reduced only up to that confirmed credit.
7. Retained G1 `0.50` receives its own net-positive protective SL.
8. G2 opens **immediately after the lock/funding sequence** and is sized from current residual Core only.
9. If residual Core = `0.75`, G2 must be `0.75` at 100% Hedge volume.
10. Retained G1 is not subtracted from G2 sizing.

Hard FAIL conditions:

- G2 = `0.25` in the canonical `Core .75 + retained G1 .50` state;
- partial close uses aggregate Hedge instead of active generation;
- floating/theoretical Hedge P/L is spent as Core-funding credit;
- G1 loses generation ownership after G2 opens;
- T8 automatically trims intentional `Hedge > Core` stacked exposure.

## Gate C — Hedge volume percentage

Run the fresh Broker preset with at least:

- 50%;
- 80%;
- 100%;
- 120%.

Expected rule:

`new generation units = floor(current residual Core units × HedgeVolumePercent / 100)`

PASS requires no upward rounding. A target below broker minimum must be rejected/fail-closed rather than silently increased.

Also record broker `SYMBOL_VOLUME_STEP`, minimum, maximum and volume-limit behavior whenever a boundary is hit.

## Gate D — Broker SL

Preset: `BlackDragon_T16_ARCS_BROKER_FRESHPASS_XAU_M1.set`.

PASS requires:

1. retained generation receives a real broker SL derived from that generation's own entry/net-BE;
2. expected SL execution is recognized as Recovery-owned, not manual/external mutation;
3. restart with an armed retained SL reconciles the reduced/closed generation correctly;
4. unknown/manual topology changes still fail closed.

## Gate E — Virtual SL

Preset: `BlackDragon_T16_ARCS_VIRTUAL_FRESHPASS_XAU_M1.set`.

PASS requires:

1. no broker SL is submitted for the virtual-protected generation;
2. virtual SL target remains durable across restart;
3. BUY-Core / SELL-Hedge closes when Ask reaches the virtual SL;
4. SELL-Core / BUY-Hedge closes when Bid reaches the virtual SL;
5. post-close layer volume/state reconcile exactly once, with no duplicate close.

## Gate F — Global SL / transition

Preset: `BlackDragon_T16_ARCS_GLOBALSL_BROKER_XAU_M1.set`.

PASS requires:

1. multiple retained generations can coexist;
2. after `GlobalSLAfterGenerations_`, Global protection is armed;
3. one common Global SL is safe/net-positive for every live retained layer under the configured target rule;
4. Core DCA is frozen while Global protection is active;
5. after Hedge stack closure the direction enters TRANSITION rather than immediately opening a blind replacement;
6. adverse continuation beyond `RecoveryReentryBufferPips_` may start a fresh ARCS generation;
7. favorable reversal enters/retains REVERSAL_HOLD.

## Evidence to return

For each run provide, preferably without editing:

- Strategy Tester Journal/log;
- Tester report or HTML if available;
- exact `.set` used;
- symbol/broker suffix and account type;
- test interval and modelling mode;
- any screenshot needed to show open positions/SL at the critical state.

The review must reconstruct this event chain from broker-observable evidence:

`Core state -> G1 open -> G1 TP partial -> realized cash -> Core funding close -> G1 lock -> G2 open -> optional further generations -> Global/SL transition`.

## Promotion rule

PR #27 remains **DRAFT / NOT BACKTEST_ELIGIBLE / NOT FORWARD_ELIGIBLE / NOT LIVE_ELIGIBLE / DO NOT MERGE** until Gates A–F have adequate runtime evidence and the exact EX5/source provenance matches this protocol.
