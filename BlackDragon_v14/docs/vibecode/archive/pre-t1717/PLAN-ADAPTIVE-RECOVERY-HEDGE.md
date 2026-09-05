# PLAN — Adaptive Recovery Hedge Integration

Status: BUILD PLAN CANDIDATE  
Method: VibeCodeKit-MQL5 Full / PLAN  
Base contract: `CONTRACT-ADAPTIVE-RECOVERY-HEDGE.md`  
Base source: `main@e3aec40547ff0328b339bbd30155dc63bff38ba9`

## 1. Goal

Integrate Adaptive Recovery Hedge into BlackDragon without contaminating legacy Core basket semantics. Implementation must be incremental, reversible, testable per slice, and keep `RecoveryMode=OFF` behaviorally equivalent to v14.9.

The implementation target is intentionally split into foundation, shadow and active-execution stages. No stage may claim runtime behavior that has not been exercised in MetaTrader Strategy Tester/forward evidence.

## 2. Non-goals for v1

Do not include in the initial build:

- ATR-adaptive hedge gaps,
- dynamic hedge ratio; v1 remains 100%,
- ML/AI parameter optimization,
- breakout/pending hedge entry,
- automatic hedge top-up after every Core DCA,
- re-hedge expansion by generation,
- arbitrary foreign/manual position recovery,
- redesign of legacy signal/grid/exit formulas,
- replacement of legacy MoneyGuard thresholds.

## 3. Delivery strategy

Use nine independently reviewable build slices. A slice may depend on earlier slices but must not silently alter unrelated legacy behavior.

### Slice A — Ownership + unit foundation

Purpose:
- create Recovery-specific types/enums/config,
- make Core-vs-Recovery ownership explicit,
- centralize price/volume helpers needed by Recovery,
- add hedging-account gate for ACTIVE only.

Expected files:
- `Config.mqh`
- `Types.mqh` or new `Recovery/RecoveryTypes.mqh`
- new `Recovery/RecoveryMath.mqh` / `PriceConvention.mqh` as justified
- tests only; no Recovery trade requests yet.

Mandatory gates:
- RecoveryMagic differs from Core Magic or fails config validation,
- Recovery OFF does not change BasketManager ownership,
- volume-unit split math unit tests,
- XAU price/pip/tick conversion tests,
- native compile 0 errors / 0 warnings.

### Slice B — Execution generalization

Purpose:
- allow execution commands to carry owner magic + Recovery metadata,
- add target-volume partial close,
- preserve position magic on close,
- support strict reconcile policy,
- preserve legacy APIs as compatibility wrappers.

Expected files:
- `ExecutionLayer.mqh`
- `Types.mqh`
- tests.

Rules:
- legacy `OpenMarket`, `ClosePosition`, `ModifySlTp` semantics stay available,
- Recovery open cannot rely on direction-global count using Core Magic,
- Recovery close uses actual target volume units,
- no Recovery state machine yet.

Mandatory gates:
- Core wrappers retain old expected behavior,
- partial-close target never rounds up,
- owner magic preserved,
- accepted async request does not equal completion,
- strict Recovery unresolved state can be surfaced without legacy bounded-release semantics being globally changed,
- native compile 0/0.

### Slice C — Registry/FSM + SHADOW mode

Purpose:
- implement two independent cycle registries,
- DCA-depth arming latch,
- anchors,
- state transitions,
- recovery metrics,
- SHADOW decisions only.

Expected new modules:
- `Recovery/RecoveryRegistry.mqh`
- `Recovery/RecoveryStateMachine.mqh`
- `Recovery/RecoveryEngine.mqh`
- optional `Recovery/RecoveryMetrics.mqh`.

No Recovery trade API calls in SHADOW.

Mandatory gates:
- BUY-Core and SELL-Core registries independent,
- off-by-one N-DCA tests,
- latch survives Core position-count shrink,
- Recovery OFF parity unaffected,
- SHADOW never mutates Core execution or blocks DCA solely due virtual pending state,
- bounded logs only.

### Slice D — HedgeBundle planner + builder

Purpose:
- create one logical generation with deterministic physical child split,
- sequential child submission/confirmation,
- aggregate target tracking,
- partial-coverage state and strict reconciliation.

Rules:
- target initial hedge = current Core units,
- re-hedge = exposure deficit only,
- one child at a time per cycle,
- physical child count never increments generation,
- `SYMBOL_VOLUME_MAX`, `SYMBOL_VOLUME_STEP`, `SYMBOL_VOLUME_LIMIT`, margin gates applied before send.

Mandatory gates:
- below max / exact max / max+step / multi-child cases,
- deterministic residual handling,
- mid-bundle failure cannot falsely transition ACTIVE,
- delayed callback/restart cannot duplicate an already-filled child,
- native compile 0/0.

### Slice E — Virtual hedge TP + realized ledger + Core allocation

Purpose:
- EA-managed soft hedge TP,
- bundle partial close,
- realized-only hedge credit,
- Core recovery close planner/executor,
- four allocation modes.

Rules:
- no broker TP used for hedge profit-taking,
- deal truth drives closed volume and cash,
- OLDEST / NEWEST / LOSSIEST-per-lot / PRO_RATA deterministic,
- no spending unconfirmed credit.

Mandatory gates:
- mixed Core lot sizes,
- bundle partial close across multiple child tickets,
- commission/swap/fee accounting cases,
- partial fill accumulation,
- actual fill differs from estimate,
- no credit crosses cycle boundary.

### Slice F — Hedge lock + re-hedge

Purpose:
- calculate net-positive hedge lock after recovery,
- broker-side protective SL allowed after lock,
- stops/freeze/tick normalization,
- re-hedge trigger and exposure-deficit sizing.

Mandatory gates:
- SELL lock remains below entry; BUY lock remains above entry when feasible,
- configured minimum + expected close-cost buffer honored,
- protection only tightens, never weakens unintentionally,
- freeze/stops reject does not advance state falsely,
- generation boundary permits generations `1..Max` and blocks starting `Max+1`,
- no unconditional second 100% hedge.

### Slice G — Core DCA + profit corridor integration

Purpose:
- implement `ContinueDcaAfterHedge_`,
- keep existing DCA chain authoritative,
- enforce allowed Recovery-state matrix,
- calculate Coverage and Corridor metrics/gates.

Rules:
- no special Recovery DCA lot/distance chain,
- Recovery children never count toward `side.count`,
- `MaxOrdersBuy/MaxOrdersSell` stay hard cap,
- no automatic hedge top-up after every DCA,
- `MinHedgeCoveragePercent_=0` disables coverage gate,
- `TargetRecoveryCorridorPips_=0` disables corridor target.

Mandatory gates:
- ContinueDCA OFF vs ON,
- mutation/reconcile states always block DCA,
- Core BE may move while hedge BE remains isolated,
- corridor sign tests for BUY-Core and SELL-Core,
- no false DCA index shift from Recovery child tickets.

### Slice H — Legacy exits, MoneyGuard, panel/mobile coordination

Purpose:
- ensure Core exit cannot leave an unintended naked Recovery hedge,
- preserve account-wide close semantics,
- coordinate cycle cleanup for magic/side/daily Core closes,
- reconcile manual intervention.

Rules:
- RecoveryMagic stays invisible to legacy side-basket detection,
- account-wide close still closes everything,
- Core-side/magic close uses recovery-aware cleanup sequencing,
- panel/mobile Core close follows same cycle safety contract,
- legacy panel open bypass semantics are not changed unless separately approved.

Mandatory gates:
- virtual TP/SL/trail/Overlap during recovery,
- MoneyGuard close buy/sell/magic/daily,
- account-wide close,
- manual Core close and manual Recovery close detection,
- no orphan/naked Recovery child after deterministic cycle cleanup completes.

### Slice I — Persistence/restart + ACTIVE release wiring

Purpose:
- dedicated Recovery persistence,
- checksum/version/integrity validation,
- broker/history reconstruction,
- startup reconciliation,
- ACTIVE mode wiring only after the prior foundations exist.

Rules:
- do not store Recovery registry in legacy panel-state struct,
- no new Recovery order before startup reconciliation completes,
- corrupt/ambiguous state => RECONCILE_REQUIRED / PAUSE_HARD,
- Recovery OFF must not create or mutate Recovery state files.

Mandatory gates:
- clean restart in each critical pending state,
- restart mid-HEDGE_BUILDING,
- restart after hedge partial close but before Core close,
- stale/missing/corrupt state file,
- broker manual intervention while terminal offline,
- dedupe already-booked deals.

## 4. Integration order in `Strategy`

Target orchestration order after ACTIVE integration:

```text
1. Consume operator close requests / emergency intents
2. Reconcile unresolved Recovery execution state
3. Account/global emergency guards
4. Recovery cycle cleanup required by Core exits
5. Recovery mutation chain (TP -> ledger -> Core close -> hedge lock)
6. Re-hedge evaluation / hedge build
7. Legacy Core exits where cycle-safe
8. Panel opens subject to existing owner-approved semantics
9. New Core series
10. Core DCA, gated by Recovery state/coverage/corridor policy
11. Legacy real Core levels
12. Timer-driven dashboard/persist/watchdog work
```

The exact call order must preserve existing rule that an active close intent is terminal for later open/DCA/modify work on that mutation chain.

## 5. Configuration surface for v1

Candidate user-facing Recovery inputs:

```text
RecoveryMode_ = OFF | SHADOW | ACTIVE
RecoveryStartAfterDca_
HedgeGapPips_
HedgeTPPips_
HedgePartialClosePercent_
CoreCloseMode_ = OLDEST | NEWEST | LOSSIEST | PRO_RATA
ContinueDcaAfterHedge_
MinHedgeCoveragePercent_
TargetRecoveryCorridorPips_
ReHedgeGapPips_
MaxHedgeGenerations_
RecoveryMagic_
```

Safety/risk inputs should reuse existing BlackDragon sources where semantics are identical. Add new knobs only where Recovery requires a genuinely distinct threshold.

Defaults:
- `RecoveryMode_=OFF`,
- fixed 100% hedge ratio,
- smart split automatic,
- virtual hedge TP,
- `CoreCloseMode_=OLDEST`,
- `ContinueDcaAfterHedge_=false`,
- coverage/corridor gates neutral (`0`) until calibrated by evidence,
- persistence/reconcile mandatory when ACTIVE, not optional user toggles.

## 6. Testing strategy

### Pure/unit layer

Extract and test deterministic helpers for:
- DCA arming count,
- volume-unit conversion/floor,
- smart split,
- exposure deficit,
- corridor sign/width,
- coverage,
- Core allocation modes,
- ledger arithmetic,
- generation bounds,
- state-transition legality.

### Offline parity layer

Extend the existing C++ offline suite only for pure logic that can be mirrored exactly. Do not create a fake broker/runtime simulation and call it MT5 evidence.

### Native compile gate

For each production-code slice:
- compile `RunTests.mq5`,
- compile `BlackDragon.mq5`,
- MetaEditor log `Result:` must show `0 errors, 0 warnings`,
- physical EX5 required for that exact tree.

Do not rerun identical compile gates if source tree has not changed.

### Strategy Tester layer

Required scenarios before behavior claims:
- Recovery OFF golden A/B,
- one-direction Recovery lifecycle,
- smart-split hedge,
- two simultaneous BUY/SELL recovery cycles,
- DCA-after-hedge OFF and ON,
- all four Core close modes,
- timeout/restart/reconciliation scenarios where tester can reproduce them,
- real-tick modeling for XAU.

### Forward demo layer

Required before forward/live promotion:
- SHADOW soak first,
- ACTIVE low-risk demo after SHADOW evidence,
- broker-specific volume/tick/freeze/stops behavior,
- reconnect/restart evidence,
- event/order/deal audit trace.

## 7. Evidence/release policy

- Documentation-only plan: no release claim.
- Static/unit + native compile: at most `BACKTEST_ELIGIBLE` when applicable gates pass.
- Strategy Tester behavior evidence required for behavioral PASS.
- Forward demo required before `FORWARD_ELIGIBLE`/`LIVE_ELIGIBLE`.
- Missing runtime capability => `UNTESTABLE`, never inferred PASS.

## 8. Risk register

### P0 — ownership contamination
Mitigation: RecoveryMagic + separate registry; explicit tests that Recovery tickets never enter BasketManager.

### P0 — duplicate/non-idempotent hedge open
Mitigation: one command/cycle, strict reconciliation, bundle child sequence, no timeout-only resend.

### P0 — naked hedge after Core exit
Mitigation: recovery-aware exit coordination before normal cycle cleanup completes.

### P1 — partial close/accounting mismatch
Mitigation: actual deal volume/cash drives ledger, integer volume units, deterministic allocation.

### P1 — DCA exposure expansion after hedge
Mitigation: explicit ON/OFF, unchanged MaxOrders, Recovery-state gate, optional coverage/corridor gate, no per-DCA hedge top-up.

### P1 — restart state drift
Mitigation: dedicated persistence + broker/history reconciliation + fail-closed ambiguity.

### P1 — smart-split partial coverage
Mitigation: HEDGE_BUILDING until aggregate target confirmed; already-filled children remain registered.

### P2 — performance/log volume
Mitigation: event-driven registry, bounded scans, transition-only logs, existing timer cadence.

## 9. Rollback model

Each build slice must be independently revertible. `RecoveryMode=OFF` is not a substitute for source rollback, but it is the runtime safety default.

Do not merge a slice that leaves production code in a half-landed state where new declarations exist without their call graph or tests.

## 10. Definition of BUILD-ready

The feature is BUILD-ready when:

- CONTRACT and PLAN are approved,
- Task Graph dependencies are explicit,
- every production slice has named files + acceptance gates,
- unresolved product choices are either locked or represented as neutral/default-off configuration,
- no remaining P0 semantic ambiguity requires implementation guesswork.
