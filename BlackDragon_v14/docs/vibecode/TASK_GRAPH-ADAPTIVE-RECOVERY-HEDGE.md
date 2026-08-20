# TASK GRAPH — Adaptive Recovery Hedge Integration

Status: BUILD TASK GRAPH CANDIDATE  
Method: VibeCodeKit-MQL5 Full / TASK GRAPH  
Depends on: `CONTRACT-ADAPTIVE-RECOVERY-HEDGE.md`, `PLAN-ADAPTIVE-RECOVERY-HEDGE.md`

## Graph

```text
T0 Contract gate
 |
 +--> T1 Ownership + unit foundation
 |      |
 |      +--> T2 Execution generalization
 |      |      |
 |      |      +--> T4 HedgeBundle builder
 |      |      |      |
 |      |      |      +--> T5 Virtual TP + ledger + Core allocation
 |      |      |             |
 |      |      |             +--> T6 Hedge lock + re-hedge
 |      |      |                    |
 |      |      |                    +--> T7 DCA/corridor integration
 |      |      |                           |
 |      |      |                           +--> T8 Legacy exit/MoneyGuard coordination
 |      |      |                                  |
 |      |      |                                  +--> T9 Persistence/restart + ACTIVE wiring
 |      |      |
 |      +--> T3 Registry/FSM + SHADOW
 |             |
 |             +---------------------------> T4
 |
 +--> TV Verification/Evidence ladder after each relevant node
```

T2 and T3 may be developed after T1; T4 requires both.

## T0 — Contract/design gate

Scope:
- SPECIFY/DECISIONS/CONTRACT/PLAN/TASK GRAPH only.

Done when:
- no unresolved P0 product semantic is left for implementation to guess,
- PR remains documentation-only,
- owner approves transition to BUILD.

Evidence:
- design review only; no compile/runtime claim.

## T1 — Ownership + unit foundation

Dependencies: T0.

Deliverables:
- Recovery enums/config structs,
- `RecoveryMode OFF|SHADOW|ACTIVE`,
- `RecoveryMagic_`,
- DCA activation helper,
- volume-unit helpers,
- XAU/general price/tick helpers reused from BlackDragon convention,
- validation that ACTIVE requires hedging account,
- validation preventing Core/Recovery magic collision.

Likely files:
- `Config.mqh`,
- `Types.mqh`,
- new `Recovery/RecoveryTypes.mqh`,
- new pure Recovery math/convention helper,
- test script/offline suite.

Must not:
- send Recovery trades,
- alter Core BasketManager ownership,
- change legacy DCA logic.

Tests:
- N-DCA count boundaries,
- integer volume units,
- floor behavior,
- XAU 2/3-digit conversion,
- Recovery OFF initialization parity.

Gate:
- static PASS,
- unit PASS,
- native MetaEditor compile 0/0.

Rollback: isolated.

## T2 — Execution generalization

Dependencies: T1.

Deliverables:
- command metadata: `ownerMagic`, cycle key, command type, strict reconcile,
- owner-aware open reconciliation,
- partial-volume close primitive,
- selected-position magic preserved on close,
- legacy APIs remain wrappers with existing semantics,
- strict Recovery uncertain outcome surfaced to caller.

Likely files:
- `Types.mqh`,
- `ExecutionLayer.mqh`,
- tests.

Must not:
- change legacy Core timeout behavior globally,
- create Recovery state machine decisions,
- silently retry unresolved Recovery OPEN.

Tests:
- owner-aware deal match,
- Core wrapper parity,
- partial close target/fill progression,
- `target <= requested`, never volume round-up,
- accepted async request != completion,
- preserve magic on close.

Gate:
- unit/offline applicable tests PASS,
- native compile 0/0.

Rollback: revert T2 without T3+.

## T3 — Registry/FSM + SHADOW

Dependencies: T1.

Deliverables:
- BUY_CORE and SELL_CORE cycle registry,
- arming latch after configured DCA depth,
- arming anchor from confirmed DCA fill,
- state-transition validator,
- coverage/corridor metrics,
- SHADOW event/decision flow,
- bounded transition audit.

Likely files:
- new `Recovery/RecoveryRegistry.mqh`,
- new `Recovery/RecoveryStateMachine.mqh`,
- new `Recovery/RecoveryEngine.mqh`,
- `BlackDragon.mq5` registration only if SHADOW wiring requires it,
- tests.

Must not:
- send Recovery trades in SHADOW,
- block Core DCA solely because a shadow command would be pending,
- allow BUY and SELL cycle ledger/state cross-talk.

Tests:
- DCA threshold N=0/1/mid/max boundaries,
- latch survives Core partial removal,
- opposite cycles independent,
- corridor sign for both directions,
- no per-tick log spam.

Gate:
- unit PASS,
- native compile 0/0,
- SHADOW runtime remains unclaimed until tester/forward evidence exists.

Rollback: independent from execution changes if T2 also exists.

## T4 — HedgeBundle smart-split builder

Dependencies: T2 + T3.

Deliverables:
- logical bundle model,
- target units,
- deterministic child plan,
- one child in flight per cycle,
- aggregate confirmed units,
- partial coverage handling,
- initial 100% hedge sizing,
- re-hedge deficit helper prepared but not full state transition yet.

Likely files:
- `Recovery/RecoveryBundle.mqh`,
- `Recovery/RecoveryEngine.mqh`,
- `ExecutionLayer.mqh`,
- tests.

Tests:
- target below max,
- target equal max,
- max + one step,
- multi-child large target,
- non-divisible residual,
- volume-limit cap/reject,
- margin gate,
- child reject/partial fill/delayed event,
- no false generation increment per child.

Gate:
- unit/offline PASS where exact,
- native compile 0/0,
- actual async broker lifecycle = UNTESTABLE until MT5 runtime evidence.

Rollback: T4 only after T2/T3 remain harmless.

## T5 — Virtual hedge TP + realized ledger + Core partial close

Dependencies: T4.

Deliverables:
- soft/virtual HedgeTP trigger,
- bundle partial-close planner,
- Recovery realized ledger,
- Core close planner,
- `OLDEST`, `NEWEST`, `LOSSIEST-per-lot`, `PRO_RATA`,
- partial-volume Core execution,
- actual-deal cash debit/credit.

Likely files:
- new `Recovery/RecoveryLedger.mqh`,
- new `Recovery/RecoveryAllocator.mqh`,
- `RecoveryEngine.mqh`,
- `ExecutionLayer.mqh`,
- tests.

Tests:
- 50% bundle close across split children,
- mixed lot child tickets,
- deal commission/swap/fee,
- actual close volume differs from request,
- all four Core allocation modes,
- deterministic pro-rata residual,
- loss-per-lot sorting,
- no negative/unconfirmed credit spend.

Gate:
- unit PASS,
- native compile 0/0,
- Strategy Tester behavior pending.

Rollback: isolated above T4 foundation.

## T6 — Hedge lock + re-hedge

Dependencies: T5.

Deliverables:
- net-positive lock calculation,
- protective broker SL only after recovery chain confirms,
- stops/freeze handling,
- lock state confirmation,
- ReHedgeGap anchor,
- `NewRequiredUnits=max(Core-Hedge,0)`,
- generation boundary logic.

Tests:
- BUY/SELL lock direction,
- tick-size normalization,
- stops/freeze reject,
- SL modification confirmation,
- no protection weakening,
- generation `1..Max` valid, `Max+1` blocked,
- hedge deficit 0 / partial / full cases.

Gate:
- unit PASS,
- native compile 0/0.

## T7 — Continue-DCA + corridor/coverage integration

Dependencies: T6.

Deliverables:
- `ContinueDcaAfterHedge_`,
- state-aware DCA gate,
- Coverage gate,
- Corridor target gate,
- legacy `TryGridAdd` remains the order-generation mechanism,
- Recovery children excluded from Core count/index.

Allowed minimum states for DCA when ON:
- `ARMED`,
- `HEDGE_ACTIVE`,
- `HEDGE_LOCKED`,
- `REHEDGE_PENDING`,
subject to contract/risk gates.

Forbidden states:
- `HEDGE_BUILDING`,
- `HEDGE_TP_PENDING`,
- `CORE_CLOSE_PENDING`,
- `HEDGE_LOCK_PENDING`,
- `RECONCILE_REQUIRED`,
- `PAUSE_HARD`,
- `GLOBAL_STOP`.

Tests:
- OFF blocks after Recovery active,
- ON keeps legacy distance/lot chains,
- MaxOrders unchanged,
- no hedge child affects DCA index,
- coverage disabled at 0,
- corridor disabled at 0,
- positive/zero/negative corridor,
- no implicit hedge top-up after DCA.

Gate:
- unit/static PASS,
- native compile 0/0,
- Strategy Tester required for behavioral PASS.

## T8 — Legacy exit / MoneyGuard / operator coordination

Dependencies: T7.

Deliverables:
- cycle-aware Core exit coordinator,
- virtual TP/SL/trailing/Overlap cleanup behavior,
- MoneyGuard magic/side/daily cleanup behavior,
- account-wide close reconciliation,
- panel/mobile manual Core close coordination,
- manual Recovery intervention detection.

Must preserve:
- legacy account-wide close scope,
- owner-approved panel-open behavior unless separately changed,
- terminal close-intent ordering.

Tests:
- Core TP while hedge active,
- Core SL/trail/Overlap while hedge active,
- MoneyGuard BUY/SELL/MAGIC/DAILY,
- account-wide close,
- operator Core close,
- operator Recovery child close,
- no cross-cycle close,
- no unintended naked hedge after complete coordinated cleanup.

Gate:
- unit/static PASS,
- native compile 0/0,
- Strategy Tester behavior required.

## T9 — Persistence/restart + ACTIVE wiring

Dependencies: T8.

Deliverables:
- dedicated Recovery persistence schema,
- version/integrity marker,
- last deal/event cursor,
- pending command metadata,
- restart broker/history reconciliation,
- ACTIVE mode enabled only after successful reconcile,
- corrupt/mismatch fail-closed.

Tests:
- clean state save/load,
- restart CORE_ONLY/ARMED/HEDGE_BUILDING/HEDGE_ACTIVE/HEDGE_TP_PENDING/CORE_CLOSE_PENDING/HEDGE_LOCK_PENDING,
- already-filled child dedupe,
- already-booked deal dedupe,
- stale/missing/corrupt registry,
- manual broker change while offline,
- Recovery OFF creates no Recovery persistence mutation.

Gate:
- static/unit PASS,
- native compile 0/0,
- Strategy Tester restart scenarios where technically reproducible,
- forward/restart evidence otherwise UNTESTABLE until demo environment.

## TV — Verification / evidence ladder

This node is continuous, not one final mega-test.

After each source-changing task:
1. targeted pure/unit tests,
2. relevant offline parity tests,
3. exact-tree native MetaEditor compile,
4. no redundant recompile if source tree unchanged.

Milestone gates:

### M1 Foundation
T1 + T2 + T3 complete.
- Recovery OFF parity structurally protected,
- SHADOW implemented,
- no live Recovery execution claim.

### M2 Recovery mechanics
T4 + T5 + T6 complete.
- bundle/ledger/lock/rehedge mechanics complete,
- native compile proven,
- behavior still requires Strategy Tester.

### M3 BD integration
T7 + T8 complete.
- DCA/corridor/legacy exits integrated,
- Strategy Tester matrix becomes mandatory.

### M4 Durable ACTIVE
T9 complete.
- restart/reconciliation durable,
- candidate may become BACKTEST_ELIGIBLE only when native compile + required test gates are satisfied.

### M5 Forward candidate
- SHADOW forward soak evidence,
- then ACTIVE demo evidence,
- only then consider FORWARD_ELIGIBLE.

## Build sequencing / PR policy

Do not implement all tasks in one unreviewable commit.

Recommended implementation PR sequence:

```text
PR-A: T1 foundation
PR-B: T2 execution generalization
PR-C: T3 SHADOW registry/FSM
PR-D: T4 bundle builder
PR-E: T5 ledger/allocation
PR-F: T6 lock/re-hedge
PR-G: T7 DCA/corridor
PR-H: T8 exits/MoneyGuard coordination
PR-I: T9 persistence/ACTIVE wiring
```

If repository workflow favors one long feature branch, preserve the same slice boundaries as commits and run the same gates after each slice.

## Stop conditions

Stop BUILD and return to CONTRACT/DECIDE if any implementation requires:
- Recovery ticket entering legacy Core basket,
- changing Core DCA counting to include Recovery children,
- spending floating/unconfirmed profit as Recovery credit,
- blind retry of unresolved Recovery OPEN,
- broker TP replacing EA-managed hedge partial TP,
- silently changing panel/manual semantics,
- auto-top-up hedge after every DCA without a new owner decision,
- cross-crediting BUY-Core and SELL-Core ledgers.
