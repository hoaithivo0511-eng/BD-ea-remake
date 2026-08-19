# T14 — Owner Strategy Tester Retest Gate

Status: **DRAFT / release blocker remains open until owner runtime PASS**.

## Baseline

- T13 product HEAD: `8416c6224f8f0880df239f9cee8e3a448f19d7a5`
- T13 product TREE: `1b7d154c531aa13ca920b04c0a0f9b4a22943d4f`
- T14 branch: `feat/adaptive-recovery-t14-execution-identity-finalization`
- T14 PR: #25 (draft, verification only; do not merge before runtime PASS)

## Runtime reproduction evidence supplied by owner

- Journal: `20260818.log`
  - SHA256: `1e3d05c4210aa705a2ccb2f4f343d1015b2e01232b7d1926fad7299b695588eb`
- Inputs: `test set.set`
  - SHA256: `20f5b08c40ac87cd1e4117d54cf2e964d66cb09dd2c6bbf90b09a6fca783cdd9`
- Scenario: Recovery ACTIVE + Hedge + account-wide Money TP + CloseAllAccount.
- Confirmed failure: account becomes flat while a stale strict Recovery execution-journal entry remains unresolved, so global flatten cannot finalize and new Core/DCA trading stays blocked.
- Confirmed secondary occurrence: a programmed Recovery protective SL can be classified as external after state advances.

## T14 verification contract

Static/model/native gates prove deterministic semantics and compilation only. They do **not** substitute for owner Strategy Tester evidence.

Required deterministic gates:

1. Full model/static suites PASS.
2. Exact T14 HEAD/TREE MetaEditor compile: `RunTests`, `RunRecoveryMutationTests`, `RunRecoveryIdentityTests`, `BlackDragon` = 0 errors / 0 warnings.
3. Native MT5 deterministic scripts:
   - `RunTests` = 246 passed / 0 failed.
   - `RunRecoveryMutationTests` = 26 passed / 0 failed.
   - `RunRecoveryIdentityTests` = 17 passed / 0 failed.
4. Exact EX5 SHA256 and evidence-package SHA256 recorded by CI.

## Owner Strategy Tester gate

Run the packaged T14 `BlackDragon.ex5` with the **exact supplied `test set.set`** and the same scenario/data range used for the reproduction where practical.

Expected sequence after Money TP All account is hit:

1. `CloseAllAccount` sends the account-wide close requests.
2. `PositionsTotal = 0`.
3. ExecutionLayer reconciliation terminalizes only journal entries that have sufficient request/order/deal/owner/cycle execution identity.
4. Truly UNKNOWN/AMBIGUOUS strict requests remain fail-closed and must print the blocking request identity.
5. `GLOBAL FLATTEN complete — atomic Recovery state persisted; ACTIVE re-armed; new Core series enabled` is reached when no genuine blocker remains.
6. When entry filters/signals allow, Core #1 opens again.
7. After adverse distance, Core DCA #2 can continue.

The former indefinite generic spam must not recur:

`account-wide close is flat but execution journal still has unresolved request(s)`

If a real ambiguous request still blocks, diagnostics must expose at least:

- requestId
- intent / commandType
- ownerMagic
- cycleKey
- retcode
- serverOrder
- serverDeal
- observedVolume / targetVolume
- positionCountBefore
- reconcileRequired
- age seconds

## Release rule

Only owner Strategy Tester evidence with the exact supplied set can promote T14 runtime status to PASS. Forward/demo delayed-fill/reject/reconnect parity remains a separate gate.

Until then:

- DRAFT
- NOT BACKTEST_ELIGIBLE
- NOT FORWARD_ELIGIBLE
- NOT LIVE_ELIGIBLE
- DO NOT MERGE MAIN
