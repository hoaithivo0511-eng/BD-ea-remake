# T17.14 OWNER STRATEGY TESTER CHECKLIST

Use only the `BlackDragon.ex5` whose HEAD, TREE, SHA-256 and size match `PROVENANCE.txt` in the T17.14 exact-head artifact.

## Required replay

- Symbol/timeframe: `XAUUSDm`, `M1`.
- Tick mode and execution delay: same as the supplied `20260828.log` (`real ticks`, `150 ms`).
- Use the same owner `.set`; record any deliberate risk-cap change separately.
- Reproduce through and beyond the original failure window around simulated `2026-06-04 12:11:41`.

## Blocking assertions

1. Twelve expected broker-SL closures interleaved with SELL Overlap do not produce `post-Overlap ARCS live-book mismatch`.
2. No repeated `T16.2 Overlap mutation remains fail-closed pending explicit reconciliation` follows an exact protective-SL batch.
3. When `Money TP All account FLOATING` reaches its threshold, `MoneyGuard CLOSE LATCHED scope=ACCOUNT` proceeds to broker close requests and `GLOBAL FLATTEN complete`/flat account state.
4. No duplicate cash funding, layer ownership consumption or global-flatten epoch appears after deferred DEAL callbacks.
5. Preserve the full tester log, `.set`, report and exact EX5 hash.

Strategy Tester remains `PENDING_OWNER` until these runtime assertions pass. Do not use forward/live trading.
