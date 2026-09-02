# T17.14 SCAN REPORT — Protective-SL/Overlap and MoneyGuard liveness

## Provenance

- Repository: `hoaithivo0511-eng/BD-ea-remake`
- PR: `#28` (`OPEN`, `DRAFT`, `UNMERGED`)
- Baseline HEAD: `e8b5a301db148c9aa797cdfa0772270125d5e036`
- Baseline TREE: `24a53f2d19c99178e02ea0332ebb689957304be0`
- Runtime log SHA-256: `298dbced0324b16d2f87c4fd46d24d52db877e9743165899769326839b4751e9`

## Confirmed runtime chain

At simulated `2026-06-04 12:11:41`, SELL Overlap latched while twelve BUY Recovery Hedge positions totaling 1.34 lots hit their expected broker SL. The synchronous broker effect was visible before deferred `OnTradeTransaction` callbacks refreshed layer ownership. Post-Overlap validation compared live zero exposure against stale persisted units, latched reconciliation and blocked Strategy for the rest of the run.

At `2026-06-04 14:09:22`, account floating exceeded the configured 100 USD Money TP and the account guard latched. `DriveGuardLatch` nevertheless returned through `RecoveryExit.HasBlockingWork()` before beginning account-wide close, so the account remained open.

## Affected composition

- ARCS protective-close history proof and layer ownership refresh.
- Post-Overlap finalization ordering.
- Recovery account-wide close idempotency.
- Strategy MoneyGuard dispatch priority.
- Deterministic/source/native verification and exact-head QA packaging.

## Preserved boundaries

- No entry, DCA, lot, coverage, target-profit or user input change.
- Unproven topology changes remain fail-closed.
- Native compile is not Strategy Tester, forward or live evidence.
