# RETRO — Adaptive Recovery T9 VERIFY

## What passed

- Exact T9 MetaEditor compile evidence remained valid; product bytes did not change during VERIFY.
- Exact T9 `RunTests.ex5` was executed in native MetaTrader 5 and returned 221 passed / 0 failed.
- Artifact SHA gating prevented accidental use of a rebuilt or stale EX5.
- Harness failures were separated from EA verdicts instead of being reported as product failures.

## What did not become testable

- GitHub-hosted MetaTrader 5 build 6116 would not start Strategy Tester without terminal account context.
- Supplying the documented `[Tester] Login=123456` emulated account value did not satisfy that platform prerequisite.
- Therefore broker-state restart, async execution timing and backtest behavior remain UNTESTABLE in this environment.

## Process corrections retained

1. Do not classify CI/harness parser defects as EA FAIL.
2. Do not fabricate demo/broker credentials to make a tester gate green.
3. Reuse the exact native build artifact and verify its digest before runtime evidence.
4. Stop opening environment workarounds once the blocker requires an external account capability.
5. Keep release at DRAFT until actual Strategy Tester evidence exists.

## Next material dependency

An authorized MT5 environment with usable terminal/demo account context (for example a controlled self-hosted runner) is required before continuing the account-backed Strategy Tester and restart matrix.
