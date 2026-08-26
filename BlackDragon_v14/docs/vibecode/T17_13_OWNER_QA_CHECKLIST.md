# T17.13 — Non-exclusive Recovery/Overlap Core Growth

Status: **BUILD COMPLETE / VERIFY PENDING**

PR #28 remains **DRAFT / DO NOT MERGE**. No live trading.

## SCAN / RRI evidence

Owner Strategy Tester log `20260827.log` proved a BUY Core chain stuck at 11 Core orders. Last Core BUY `#234` opened near `4091.635`; with the configured next DCA spacing `13 pip` (Gold unified input unit `0.10 USD/pip`), the next Core DCA was due near `4090.335`. Price later traded near `4049.197`, yet no Core DCA was submitted.

Two independent read-only ownership gates were identified:

1. Overlap `PAIR_ARMED` returned `WAIT` but `BlocksSide(BUY)` still prevented same-side Pyramid/DCA admission.
2. Recovery `HEDGE_BUILDING` blocked `CRecoveryDcaFilter` even with `ContinueDcaAfterHedge_=true`; Core Pyramid ADD was also blanket-blocked whenever Recovery owned the side.

## DECISION / CONTRACT

The scheduler contract is now **mutation ownership, not state ownership**:

- Read-only Recovery/Overlap WAIT does not exclusively own the Core side.
- Only actual broker mutation in flight, pending execution, or reconcile ambiguity may hard-block new Core growth.
- Existing `ContinueDcaAfterHedge_` controls whether Core DCA and Core Pyramid ADD may grow while Recovery is in read-only Hedge states. No new user input is added.
- Allowed concurrent Recovery public states when `ContinueDcaAfterHedge_=true`: `HEDGE_BUILDING`, `HEDGE_ACTIVE`, `HEDGE_LOCKED`, `REHEDGE_PENDING`.
- Pending TP/Core-close/lock/protect/reconcile/global-stop states remain fail-closed.
- Core Pyramid **ADD** gains the same concurrency; Core Pyramid Peel/close remains blocked while Recovery owns the side to avoid an unplanned Core shrink / over-hedge transition.
- One broker mutation chain per Strategy tick remains intact. If Recovery or Overlap actually submits/mutates, it wins that tick.
- Overlap pre-leg economics/Recovery DEFER is a soft candidate. Durable execution identity is required only once leg1 is immediately executable; already-submitted/reconcile states retain durable restart safety.
- Existing MaxOrders, timing, pause/news, NO_MONEY, margin, risk-budget, execution-journal and REAL-TP same-side barriers remain authoritative.
- Hedge Pyramid BUILDING continues to rebase its persisted generation target from live Core units before further Hedge mutation.
- No persisted enum renumbering; no T17.10 unit semantic changes; no T17.9/T17.11 rollback.

## Owner Strategy Tester acceptance

Use the same configuration family as `20260827.log` and exact final EX5 provenance.

1. Reproduce a Core BUY chain reaching the Recovery threshold with `ContinueDcaAfterHedge_=true`.
2. If Recovery Hedge Pyramid is `BUILDING` and merely waiting for its next Hedge gap, a Core DCA that satisfies its own spacing/filter rules must still be submitted.
3. The 11-BUY counterexample must not remain frozen: after last Core around `4091.635`, next spacing `13 pip`, price at/through about `4090.335` must make DCA #12 reachable unless a different explicit blocker is logged.
4. A read-only Overlap candidate/old `PAIR_ARMED` must not suppress same-side DCA or Core Pyramid ADD.
5. Ordinary pre-leg Overlap economics WAIT must not leave a durable blocking pair. The candidate may be re-evaluated after the basket changes.
6. Once Overlap leg1 or leg2 is actually submitted, Core growth stays serialized until the broker outcome is known. `RECONCILE` remains fail-closed.
7. Core Pyramid ADD may execute during read-only Recovery ownership when its own favorable geometry/economic/risk rules pass. Peel remains Recovery-owned blocked.
8. After any Core DCA/Core Pyramid ADD during `HEDGE_BUILDING`, Recovery must log/recompute a new Hedge target from the new live Core denominator before the next Hedge ADD. No stale target or over-persisted generation is allowed.
9. `ContinueDcaAfterHedge_=false` must retain the old Core-growth block under Recovery ownership.
10. MoneyTPAllAccount immediate-close behavior from T17.12 owner correction must remain intact; no `MoneyTP ACCOUNT WAIT` may return.
11. No regression in T17.5–T17.12, including T17.9 REAL-TP durability, T17.10 units and T17.11 scheduler/no-money protections.
12. Tester must reach the requested end date without unexplained premature termination or silent Core-growth starvation.

Until exact EX5 owner Strategy Tester evidence passes: **OWNER RELEASE GATE = PENDING; FORWARD/LIVE = NOT ELIGIBLE.**
