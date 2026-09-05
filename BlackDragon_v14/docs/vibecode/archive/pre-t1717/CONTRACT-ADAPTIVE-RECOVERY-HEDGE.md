# CONTRACT — Adaptive Recovery Hedge Integration

Status: IMPLEMENTATION CONTRACT CANDIDATE  
Method: VibeCodeKit-MQL5 Full / CONTRACT  
Base: `main@e3aec40547ff0328b339bbd30155dc63bff38ba9`

This contract is the implementation boundary for the Adaptive Recovery Hedge subsystem. If implementation needs to violate an invariant below, stop and revise this contract first.

## 1. Release behavior contract

### Recovery OFF

`RecoveryMode=OFF` MUST preserve existing BlackDragon v14.9 Core behavior.

Mandatory parity:

- same Core position ownership,
- same DCA count/index semantics,
- same lot and distance chains,
- same `MaxOrdersBuy/MaxOrdersSell` hard caps,
- same MoneyGuard behavior,
- same TP/SL/trailing/Overlap behavior,
- same manual magic-0 semantics,
- same panel/manual order semantics unless separately approved,
- no Recovery positions, files, trade requests or Recovery-ledger mutations.

### Recovery SHADOW

- May calculate Recovery state, hedge sizing, split plan, recovery cash plan and corridor metrics.
- MUST NOT send Recovery open/close/modify requests.
- MUST NOT block Core DCA solely because a shadow Recovery mutation would have been pending.
- May emit bounded audit evidence; must not flood per-tick logs.

### Recovery ACTIVE

- Executes the state machine and all safety invariants below.

## 2. Account-mode gate

Recovery ACTIVE requires `ACCOUNT_MARGIN_MODE_RETAIL_HEDGING`.

- If not hedging mode: Recovery ACTIVE initialization must fail closed or Recovery must be explicitly disabled before any Recovery request can be sent.
- Core legacy behavior under Recovery OFF must not be broken by this gate.

## 3. Ownership invariant

Core domain:

```text
ownerMagic = Magic
manager = CBasketManager
roles = CORE only
```

Recovery domain:

```text
ownerMagic = RecoveryMagic_
manager = CRecoveryManager / CRecoveryRegistry
roles = HEDGE only
```

Invariant:

> A Recovery ticket must never be counted in `m_basket.buy` or `m_basket.sell`.

Every Recovery child must be attributable to:

```text
CycleDirection + Generation + BundleId + ChildIndex + RecoveryMagic
```

Comments may assist human audit but broker ticket/deal state + owner magic + persisted registry are the authoritative relationship evidence.

## 4. Cycle model

At most two Core recovery cycles exist for the chart symbol:

```text
BUY_CORE  -> SELL hedge
SELL_CORE -> BUY hedge
```

Each cycle owns independently:

- state,
- arming latch,
- activation/rehdge anchors,
- Core ticket references/snapshots,
- logical HedgeBundles,
- active hedge child tickets,
- generation count,
- pending command identity,
- realized recovery ledger,
- last processed deal/event cursor,
- pause/reconcile reason.

No Recovery cash or command state may cross cycles.

## 5. State machine contract

Minimum states:

```text
CORE_ONLY
ARMED
HEDGE_BUILDING
HEDGE_ACTIVE
HEDGE_TP_PENDING
CORE_CLOSE_PENDING
HEDGE_LOCK_PENDING
HEDGE_LOCKED
REHEDGE_PENDING
PAUSE_SOFT
PAUSE_HARD
RECONCILE_REQUIRED
GLOBAL_STOP
COMPLETED
```

Key transitions:

```text
CORE_ONLY
  -> ARMED
     when configured DCA threshold is first confirmed

ARMED
  -> HEDGE_BUILDING
     when adverse HedgeGap is hit and risk gates pass

HEDGE_BUILDING
  -> HEDGE_ACTIVE
     only after aggregate confirmed child volume reaches planned bundle target

HEDGE_ACTIVE
  -> HEDGE_TP_PENDING
     when virtual hedge TP is hit

HEDGE_TP_PENDING
  -> CORE_CLOSE_PENDING
     only after actual hedge-closing deals are reconciled and realized cash is booked

CORE_CLOSE_PENDING
  -> HEDGE_LOCK_PENDING
     only after actual Core-closing deals are reconciled

HEDGE_LOCK_PENDING
  -> HEDGE_LOCKED
     only after protection state is observable/reconciled

HEDGE_LOCKED
  -> REHEDGE_PENDING
     when recovery cycle remains active and a future re-hedge may be required

REHEDGE_PENDING
  -> HEDGE_BUILDING
     when re-hedge gap/risk gates pass and exposure deficit > 0
```

Any ambiguous broker state may transition to `RECONCILE_REQUIRED`; no new Recovery/Core-DCA mutation is allowed there.

## 6. Activation/counting contract

`RecoveryStartAfterDca_` counts DCA additions, not the initial Core entry.

```text
Core open position count = 1 -> dcaCount 0
Core open position count = 2 -> dcaCount 1
...
```

When threshold is first crossed:

- latch `recoveryArmed=true`,
- store confirmed arming DCA deal/ticket/price,
- do not later un-arm because position count shrinks.

No off-by-one interpretation is permitted.

## 7. Hedge sizing contract

Initial target hedge:

```text
TargetHedgeUnits = CurrentCoreUnits
```

v1 ratio is fixed 100%.

Re-hedge target:

```text
NewRequiredUnits = max(CurrentCoreUnits - ActiveRecoveryHedgeUnits, 0)
```

No request may round aggregate hedge exposure above the computed target.

## 8. Smart-split contract

HedgeBundle planning must operate in integer volume units.

For every bundle:

1. read/validate symbol volume metadata,
2. compute target units,
3. respect per-order maximum,
4. respect aggregate `SYMBOL_VOLUME_LIMIT`,
5. check margin/risk before child submission,
6. submit one child at a time for that cycle,
7. confirm each child from broker-observable state before submitting the next.

A physical child is NOT a new generation.

If a split fails mid-bundle:

- keep already-filled child positions registered,
- mark partial coverage,
- reconcile before retry,
- do not claim `HEDGE_ACTIVE` until target is confirmed or policy explicitly accepts a bounded residual,
- unresolved state => `RECONCILE_REQUIRED` / fail-closed.

## 9. Execution contract

All trade API calls remain inside `CExecutionLayer` or a Recovery execution gateway implemented as part of/refactoring that same execution boundary. No Recovery engine may call `OrderSend*` directly.

Execution requests require metadata sufficient to reconcile independently of legacy Core assumptions:

```text
ownerMagic
cycle key
command type
bundle/generation
position ticket when applicable
target volume units
strict-reconcile policy
```

Recovery OPEN is non-idempotent and must never be blindly re-sent after timeout.

Recovery CLOSE/MODIFY may only retry after broker state/history reconciliation proves the intended effect is absent or incomplete.

Accepted async request is not completion.

## 10. Partial-close execution contract

The execution layer must support closing a target volume, not only whole-ticket close.

For Recovery hedge partial close and Core recovery close:

- target volume represented in integer units,
- never round upward,
- preserve selected position owner magic on closing request,
- correlate actual closing deal volume,
- partial fills accumulate until target is satisfied or a fail-closed condition occurs,
- realized cash comes from actual closing deals.

## 11. Recovery ledger contract

Cycle ledger is realized-only for accounting.

Credit sources:

```text
confirmed Recovery hedge closing deals
= DEAL_PROFIT + DEAL_SWAP + DEAL_COMMISSION + DEAL_FEE when available/appropriate
```

Debit sources:

```text
absolute realized loss/cost of confirmed Core recovery-closing deals
```

Planning MAY use floating mark-to-market estimates to choose which Core volume can probably be closed. Accounting MUST use actual realized deals.

Credit must never become negative merely because planned loss differed from fill reality. If an actual fill would exceed available credit under the configured policy, remaining recovery actions must pause/reconcile rather than silently spend nonexistent credit.

## 12. Core close allocation contract

Four modes are supported:

### OLDEST
- tickets oldest first.

### NEWEST
- tickets newest first.

### LOSSIEST
- rank by current loss-per-lot, most negative first.
- absolute total loss must not be used as the ranking metric.

### PRO_RATA
- target units distributed proportionally across eligible Core tickets.
- deterministic residual-unit allocation.
- never exceed target units or available recovery credit.

All modes must be tested with mixed lot sizes and partial-ticket closes.

## 13. Continue-DCA contract

`ContinueDcaAfterHedge_=false`:
- Core DCA is blocked after active Recovery begins according to FSM policy.

`ContinueDcaAfterHedge_=true`:
- use existing BlackDragon `TryGridAdd` semantics and existing lot/distance chain only,
- retain `MaxOrdersBuy/MaxOrdersSell` hard cap,
- Recovery hedge children do not count toward Core DCA position count,
- DCA forbidden whenever current Recovery state has a mutation/reconciliation chain in flight.

Allowed-state policy must be explicit and unit-tested; at minimum `HEDGE_BUILDING`, `HEDGE_TP_PENDING`, `CORE_CLOSE_PENDING`, `HEDGE_LOCK_PENDING`, `RECONCILE_REQUIRED`, `PAUSE_HARD`, `GLOBAL_STOP` forbid DCA.

## 14. Corridor and coverage contract

Metrics:

```text
BUY Core cycle:
CorridorPrice = HedgeSellNetBE - CoreBuyNetBE

SELL Core cycle:
CorridorPrice = CoreSellNetBE - HedgeBuyNetBE
```

Coverage:

```text
CoveragePercent = ActiveRecoveryHedgeUnits / CurrentCoreUnits * 100
```

- If `CurrentCoreUnits <= 0`, cycle completion/cleanup logic applies instead of division.
- `MinHedgeCoveragePercent_=0` disables coverage-based DCA gating.
- `TargetRecoveryCorridorPips_=0` disables corridor-target DCA gating.
- Non-zero thresholds require explicit user configuration/evidence; implementation must not invent them.

## 15. Legacy exit and MoneyGuard integration contract

Recovery positions must not trigger legacy side detection simply by existing in the opposite direction.

Core exit while Recovery is active must be cycle-aware:

- legacy Core TP/SL/trailing/Overlap,
- panel/manual Core close,
- MoneyGuard Core/magic close,
- daily close,

must not leave an unintended naked Recovery hedge.

A coordination layer must turn a Core close intent into a cycle-consistent cleanup/reconcile sequence when Recovery is active.

Account-wide close remains account-wide and therefore naturally includes Recovery positions; Recovery registry must reconcile/complete afterward.

## 16. Parallel-cycle command contract

- Maximum one mutation command in flight per Recovery cycle.
- BUY-Core and SELL-Core cycles may each have one independent command in flight if account-level rate/risk limits allow.
- Global/account emergency action preempts normal Recovery scheduling.

## 17. Persistence/restart contract

Recovery state must not be stored only in the legacy small panel-state struct.

Dedicated Recovery persistence must include at least:

- schema/version,
- cycle direction/id,
- FSM state,
- arming latch/anchor,
- generation/bundle metadata,
- known Recovery tickets,
- ledger/credit,
- pending command identity/version,
- last processed deal/event cursor,
- integrity marker/checksum or equivalent validation.

On restart:

1. load persisted registry,
2. scan broker positions/deals for Core and Recovery ownership,
3. reconcile actual state,
4. do not send a new Recovery order before reconciliation completes,
5. mismatch that cannot be proven safe => `RECONCILE_REQUIRED` / `PAUSE_HARD`.

## 18. Price/unit contract

Recovery must reuse one BlackDragon price convention for XAU/Forex.

- XAU convention remains 1.00 price = 10 pips / 1 pip = 0.10 price.
- Trigger and stored recovery anchors should use normalized/integer tick representations where practical.
- All broker prices normalized to `SYMBOL_TRADE_TICK_SIZE`.
- stops/freeze levels checked before Recovery SL modification.
- volume arithmetic uses volume units.

## 19. Logging/performance contract

- No per-tick state spam.
- Log state transitions, command submission/final outcome, reconciliation anomaly, realized ledger mutation and hard safety events.
- Repeated stable-state observation is silent.
- `OnTradeTransaction` remains minimal; expensive reconciliation/ledger/persistence work runs outside the hot transaction callback where possible.
- Reuse existing BlackDragon timer cadence rather than creating an independent competing timer lifecycle.

## 20. Acceptance matrix before BUILD can be called complete

### Core parity

- Recovery OFF: exact intended v14.9 Core behavior retained.
- Recovery tickets excluded from Core baskets.
- Core DCA order index ignores Recovery physical children.

### Activation

- N=0/1/boundary behavior specified and tested.
- arming latch survives partial Core ticket removal.

### Bundle

- required volume below max => one child.
- exact max => one child.
- max + one step => two children.
- large target => deterministic split.
- below-min residual => never rounded up.
- partial child failure => no false ACTIVE state.

### Async/idempotency

- accepted request without state effect stays pending.
- delayed event cannot create duplicate hedge.
- timeout causes reconciliation before retry.
- restart during HEDGE_BUILDING reconstructs already-filled children.

### Partial hedge/Core close

- actual deal volumes drive completion.
- actual realized cash drives ledger.
- all four Core allocation modes pass mixed-size baskets.

### Continue DCA

- OFF blocks appropriately.
- ON preserves legacy DCA chain and MaxOrders.
- no DCA during Recovery mutation states.
- new Core DCA changes coverage/corridor metrics without contaminating hedge ownership.

### Parallel cycles

- BUY and SELL recovery ledgers remain independent.
- simultaneous cycles do not cross-close/cross-credit.
- account emergency action reconciles both.

### Restart/corruption

- clean restart restores/reconciles cycle.
- broker-side manual intervention is detected.
- corrupt/mismatched registry fails closed.

## 21. Evidence gates

Implementation release level cannot exceed evidence obtained.

- Static/unit/native compile only -> at most BACKTEST_ELIGIBLE when compile gate and required static tests pass.
- Strategy Tester scenarios required for behavior claims.
- Forward demo evidence required before FORWARD/LIVE promotion according to VibeCodeKit release policy.
- Missing runtime infrastructure is `UNTESTABLE`, never PASS.
