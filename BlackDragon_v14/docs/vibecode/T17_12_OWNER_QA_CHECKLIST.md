# T17.12 Owner Strategy Tester QA Checklist

Status gate: **PENDING until exact EX5 owner Strategy Tester evidence passes.**

PR #28 remains **DRAFT / DO NOT MERGE**. No live trading.

## Exact artifact identity

Before every tester run record from the final artifact:

- HEAD commit SHA.
- TREE SHA.
- `BlackDragon.ex5` SHA256.
- `BlackDragon.ex5` file size.
- GitHub Actions run ID / attempt.
- Artifact ID / artifact digest.
- Terminal/MetaTrader build.
- Exact `.set`, symbol, timeframe, test model, account balance/leverage/margin mode, start/end dates.

Do not accept an EX5 whose hash/size does not match the exact-head artifact.

## P0-A — Recovery-aware economic exits

1. Re-run the previously failing Recovery TP families represented by whole-cycle counterexamples around `-342.09 USD` and `-210.30 USD`.
2. Virtual TP: Core TP price may trigger first, but no Recovery-owned full-side close may start unless current whole-cycle liquidation cash funds nominal TP objective plus reserve.
3. Core-only virtual TP parity must remain unchanged.
4. REAL TP under Recovery ownership must be Recovery-aware, not Core-only.
5. BUY and SELL under-hedged cases: broker TP may shift only outward and must remain finite/economically funded.
6. Fully hedged / over-hedged / invalid tick-economics cases: unsafe broker TP must not be programmed.
7. T17.9 REAL-TP durable cohort identity, same-side ADD barrier, TP classification, settlement and restart replay must remain intact.
8. Virtual and REAL trailing: legacy `iTS/iTD` arm/hit/extreme semantics stay unchanged; Recovery-owned profit-taking mutation waits if whole-cycle reserve is not funded.
9. Independent REAL SL risk protection must not be disabled by the T17.12 profit-taking gate.
10. No negative whole-cycle TP/Trail close attributable to Core-vs-Recovery economic-domain mismatch.

## P1-B — Overlap same-pair liveness

1. Overlap remains a same-side pair: winning/newer leg closes first, losing/older leg second.
2. Temporary pre-leg1 economics failure keeps the exact durable pair armed; it must not emit successful ARM/persist every tick.
3. Recovery DEFER/WAIT is read-only for the pair obligation.
4. Actual broker-realized leg1 cash from history funds leg2 together with current leg2 floating and execution reserve.
5. Proven stale/missing ticket or externally changed locked volume may cancel the obligation once; ordinary economic WAIT may not.
6. Opposite-side scheduling remains eligible during read-only WAIT.

## P1-C — MoneyTPAllAccount execution erosion

1. `MoneyTPAllAccount` still arms on raw current `ACCOUNT_PROFIT >= configured target` before any new risk mutation.
2. Once armed, Seed/DCA/Pyramid/Recovery ADD remains blocked even if floating retreats.
3. Before the first new account-flatten mutation, current floating must fund target plus conservative account-scope close reserve.
4. Reserve must include all current account positions across symbols/magics using each symbol's live spread, tick size/value and configured deviation conversion.
5. Missing symbol/tick metadata waits fail-closed; it must not fall back to zero reserve.
6. Once flatten admission opens, the sequential close-to-flat chain is not re-gated by later price retreat.
7. `MoneySLAllAccount` and other MoneyGuard scopes retain their previous behavior.
8. Record realized close-group outcome; target+reserve is a conservative admission policy, not a claim of impossible-to-breach broker execution guarantee.

## P2-D — invalid init lifecycle

1. Use an intentionally invalid Recovery config that returns `INIT_PARAMETERS_INCORRECT` before `g_recovery.Init()`.
2. `OnDeinit()` must not emit a false ARCS temp-state/persistence error (previous symptom included `LastError=5002`).
3. Valid initialized Recovery persistence behavior must remain unchanged.

## Regression gate T17.5–T17.11

Verify no regression in:

- T17.5 durable Pyramid campaign accounting / economic TP / PctDiff reserve.
- T17.6 Pyramid hardening and DCA reachability.
- T17.7 scheduler, anchor, durable Overlap, Hedge ladder, migration and journal.
- T17.8 persistence-only yield/runtime fixes.
- T17.9 REAL broker TP identity/durability/restart settlement.
- T17.10 point/pip/tick semantics and frozen Hedge coverage semantics.
- T17.11 scheduler starvation, terminal-no-Hedge and NO_MONEY cross-tick admission.

## Release decision

PASS requires exact-artifact tester evidence for every applicable item above and the requested tester period reaching its end without unexplained premature termination.

Until then: **OWNER RELEASE GATE = PENDING; PR = DRAFT / DO NOT MERGE; FORWARD/LIVE = NOT ELIGIBLE.**
