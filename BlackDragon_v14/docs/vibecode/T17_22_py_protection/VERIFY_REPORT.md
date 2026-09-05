# T17.22 Verification Report — Core Pyramid Group Protection

Status: `IMPLEMENTED_LOCAL_VPS_VERIFIED_CI_PENDING`
Method: VibeCodeKit MQL5 Full
Release/forward/live/merge: `false`

## Scope and locked behavior

T17.22 adds independent group-level protection for actual Core Pyramid BUY and SELL positions. The feature is disabled by default and has `OFF`, `VIRTUAL`, and `BROKER` modes. It reuses the existing basket, execution, deal-history, and Recovery finalization paths rather than adding a second whole-account engine.

Protection economics are scoped to the exact active PY episode. A group can arm only from its own live and booked net cash after swap, commission, fee, exit reserve, configured safety, and slippage reserve. BUY stop price can only rise; SELL stop price can only fall. Optional trailing shares the same monotone rule.

After PY closes, the adapter invalidates cached topology, rebuilds from live positions and exact deal fills, checks the post-PY RH cap, trims excess RH if required, then asks Recovery to validate/rebase. The next PY episode increments its serial and excludes old member cash, lot, and weighted price. It does not reuse the preceding episode's calculation inputs.

## Defects found by native broker testing

Two callback-order defects were found and fixed before publication:

1. A broker SL could execute on the same market event that acknowledged the newest SL modification. The position was already closed before the transient executor proof could be read, while `confirmedSl` still held the previous price. The classifier now accepts the exact durable `requestedSl` written before the broker side effect; a definitive reject rolls that value back.
2. MT5 could deliver a later notification for the same SL deal after the group had already settled to `FLAT`. Current-episode members are retained as exact tombstones. The same position identifier, broker mode, episode serial, `DEAL_REASON_SL`, and programmed stop price remain sufficient for the delayed bypass. Starting a new episode increments the serial and invalidates the old tombstone.

The first defect initially caused Recovery to classify a PY broker SL as an external/manual Core mutation. The second could reproduce the latch after a valid FLAT. Both previously produced `reconcile required`; the final BROKER job contains neither condition.

A related liveness guard was added: flat settlement waits while execution or Recovery ownership is pending/fail-closed before doing an exposure scan. In the failing exploratory run, the stale settlement path performed 55,747 exposure scans. The final BROKER run performed 25 exposure scans and 146 position visits over 56,428 tester ticks.

## Verification matrix

| Layer | Result |
|---|---|
| C++ model regression | 41/41 suites PASS |
| T17.22 pure model | 45 passed / 0 failed |
| T17.22 source contract | 54 passed / 0 failed |
| Repository contract | 9 passed / 0 failed |
| JSON/YAML parse and `git diff --check` | PASS |
| Deep review Stage 0–7 | 4 critical / 55 error / 385 warn / 31 info; no critical/error increase over T17.21 debt baseline |
| VPS MetaEditor compile | 0 errors / 0 warnings |

Final staged compile source:

- SHA-256: `27d429dd8686fc061e258600a319fecfce71370d9196dbfb98b761bb6ac944ec`
- Compile evidence: `COMPILE-1788573649724`
- Standalone EX5 SHA-256: `b8ed0216d4a986a627e43bd4cf63bcfb4b93eb35aa9950bd20bcce71561b4392`
- Standalone EX5 size: `726602` bytes

The stage is the canonical EA plus 89 exact dependency bodies flattened only because the Tunnel deploy path does not mirror the repository Include tree. Canonical repository sources remain modular.

## Final Strategy Tester evidence

All final jobs used MT5-2 build 6140, `EURUSDm`, M5, model 1, 2026-08-21 through 2026-09-04, Visual off, and 100% analyzed history quality. Profit is not an acceptance gate.

| Mode | Job | Runtime evidence |
|---|---|---|
| T17.21 exact baseline | `BT-20260905-040227-37A938` | 56,428 ticks; 2,877 bars; 31 trades / 60 deals |
| T17.22 OFF | `BT-20260905-090123-C7ED93` | Exact equality with baseline for ticks, bars, trades, deals, P/L, and drawdown; no fatal/diagnostic/anomaly |
| T17.22 VIRTUAL | `BT-20260905-090439-145840` | BUY and SELL `ARMED → FLAT`; new serial/fills after each close; 46 exposure scans, 286 visits; no error/reconcile/fatal |
| T17.22 BROKER | `BT-20260905-090755-A05982` | Real position SL modifications and broker-triggered closes; 2 BUY and 9 SELL episodes settled; 25 exposure scans, 146 visits; no error/reconcile/fatal |

VIRTUAL used deliberately small test-only thresholds and one-minute OHLC ticks. Two virtual settlements crossed a very small positive floor and filled slightly negative because the next modeled quote jumped beyond the virtual stop. This is a virtual-stop gap/slippage limitation, not stale episode accounting. Production defaults are OFF with trigger/lock/safety/trailing `10/3/1/0` pips and are not presented as owner-optimized parameters.

Natural tester paths did not require an RH trim (`trim=0`). Deterministic model/native contracts cover the forced post-PY cap, RH trim accounting, no false funding credit, exactly-once replay, fresh rebase, restart, partial, and ambiguous-outcome paths. A favorable live-style PY-and-RH coexistence case that actually emits a trim remains an owner Strategy Tester acceptance item.

## Remaining gates

- Exact remote-parent Git-data publication and exact-head GitHub CI are pending at this report revision.
- GitHub native matrix must compile the full EA and all 31 scripts with 0 errors/0 warnings and execute 1,075 assertions with 0 failures.
- Owner Strategy Tester acceptance, broker variants, forward testing, economic parameter selection, release, merge, and live trading remain pending/disabled.
