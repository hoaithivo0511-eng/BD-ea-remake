# T16.3 — ARCS Liveness Fix

Status: **DRAFT / owner Strategy Tester retest required / DO NOT MERGE**.

## Runtime evidence that triggered T16.3

Owner T16.2 Strategy Tester log proved two independent liveness failures after Overlap itself had already completed successfully:

1. A retained generation stayed in `HEDGE_LOCK_PENDING` for hours while the positive broker SL was not yet placeable. There was no pending execution command and no ambiguous broker outcome, yet Recovery consumed every tick and starved legacy Core DCA even with `ContinueDcaAfterHedge_=true`.
2. After generation `G30` reached `MaxHedgeGenerations_=30` and the remaining Hedge exposure later closed by protective SL, Core exposure remained but Recovery fell into the `REVERSAL_HOLD -> PAUSE_SOFT` scheduling view. G31 was correctly forbidden, but Core DCA was also blocked forever.

## Contract

T16.3 does **not** change the approved ARCS trading semantics:

- `MaxHedgeGenerations_` remains a hard ceiling. `G(Max+1)` is forbidden.
- The generation counter is not reset merely to bypass the ceiling.
- Retained Hedge protection remains mandatory before a new Recovery generation.
- Timeout/connection/ambiguous execution outcomes remain fail-closed.
- `OverlapAfterHedge_` coordination and T16.2 post-Overlap refresh remain unchanged.

### A. Deferred lock yield

When all of the following are true:

- Recovery `Drive()` reached the retained-generation lock path;
- broker SL is temporarily not placeable by fresh stops/freeze geometry, **or** broker explicitly rejected the MODIFY with deterministic no-effect;
- no execution command is pending for that Recovery cycle;
- no execution reconciliation is required;

then Recovery may yield the remainder of that tick to legacy Core DCA.

Scheduling view for that tick is `REHEDGE_PENDING` because the existing T7 policy treats it as DCA-stable while T8 still defers Overlap. Internal ARCS phase remains `LOCK_PENDING`; the next tick retries the lock before Core work.

A real pending MODIFY or ambiguous outcome still consumes the tick and blocks Core mutation.

### B. Maxed-no-Hedge terminal management

When:

- `generationCount >= MaxHedgeGenerations_`;
- live Recovery Hedge exposure is zero;
- Core exposure is still positive;
- internal ARCS is in its terminal locked/reversal hold region;

T16.3 derives the semantic condition `MAXED_NO_HEDGE`.

Behavior:

- no new Recovery generation is allowed;
- `ContinueDcaAfterHedge_=true` may continue the existing legacy Core DCA chain;
- normal DCA coverage/corridor gates remain authoritative;
- stable Overlap may continue when `OverlapAfterHedge_=true`;
- account/global risk controls remain unchanged;
- when Core eventually becomes flat, the existing lifecycle may reset the direction normally.

The compatibility scheduling view is `HEDGE_LOCKED`; this is not used to claim live Hedge exposure. `SRecoveryCycle.activeHedgeLots` continues to report the broker-observed zero Hedge volume, and runtime emits an explicit `T16.3 MAXED_NO_HEDGE` diagnostic.

## Verification requirements

Deterministic gates on the exact source tree must prove:

1. deterministic lock wait + journal quiet => DCA yield;
2. pending MODIFY => no yield;
3. ambiguous execution => no yield;
4. deferred lock scheduling => DCA stable, Overlap deferred;
5. G29 may start G30 when Max=30;
6. G30 may not start G31;
7. G30 + Hedge=0 + Core>0 => Core management remains live;
8. maxed scheduling permits DCA and stable Overlap;
9. pre-Max / Core-flat / Hedge-still-live cases do not falsely enter maxed terminal handling;
10. all T1–T16.2 gates remain green.

## Owner runtime retest

Use the same owner Strategy Tester scenario that reproduced T16.2 starvation.

Required evidence:

- During the former hours-long lock wait, Journal may show `T16.3 deferred-lock yield`; qualifying Core DCA must no longer be blocked solely because the retained Hedge SL is temporarily unplaceable.
- After G30 and all Recovery Hedge exposure reaches zero while Core remains, Journal must show `T16.3 MAXED_NO_HEDGE` and must not repeat `Core DCA blocked by Recovery state=PAUSE_SOFT` solely from the max-generation condition.
- No G31 may open.
- Existing T16.1/T16.2 protective-SL, explicit-reject, Overlap and execution-identity behavior must remain clean.

Until this owner runtime gate passes: **NOT BACKTEST_ELIGIBLE / NOT FORWARD_ELIGIBLE / NOT LIVE_ELIGIBLE / DO NOT MERGE**.
