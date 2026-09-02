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

## P1-C — MoneyTPAllAccount immediate-close owner correction

Owner Strategy Tester log `20260827.log` supersedes the earlier reserve-pre-admission contract. The old behavior latched at approximately `+100.02 USD` but waited for approximately `+160.68 USD`, then blocked Strategy mutations while floating retreated. That runtime behavior is a release-blocking liveness failure and must not recur.

1. `MoneyTPAllAccount` is a direct raw-current-floating close threshold: `ACCOUNT_PROFIT >= configured target` triggers account close-to-flat.
2. On the trigger tick the Strategy latches `GUARD_CLOSE_ACCOUNT` and begins the existing account-wide flatten path immediately; there is no `target + reserve` price-recovery admission gate.
3. No `MoneyTP ACCOUNT WAIT`, `MoneyTP ACCOUNT ADMITTED`, account-TP reserve state, or equivalent pre-close profit wait may exist.
4. Existing async safety serialization remains valid: if a broker OPEN/CLOSE outcome is already in flight, Strategy may wait for that broker outcome before sending a contradictory close, but it must not wait for floating profit to recover above the configured MoneyTP.
5. Once the close-to-flat chain has begun, the existing MoneyGuard latch remains authoritative until the account scope is flat even if floating retreats during sequential broker execution.
6. Account scope remains the legacy all-account scope; no new symbol/magic/user-input restriction is introduced.
7. `MoneySLAllAccount` and all other MoneyGuard scopes retain their prior behavior.
8. Record trigger floating and realized close-group outcome. The configured MoneyTP is a trigger threshold, not a guaranteed realized floor after spread/slippage/sequential execution.

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
