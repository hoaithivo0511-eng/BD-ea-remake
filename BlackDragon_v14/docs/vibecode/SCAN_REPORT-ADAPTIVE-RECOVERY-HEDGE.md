# SCAN REPORT — Adaptive Recovery Hedge

Date: 2026-08-17 (Asia/Ho_Chi_Minh)  
Method: VibeCodeKit-MQL5 Full / SCAN  
Product implementation head: `1d323c2afcc213dcd6eaaa296eb71a20788a8de9`  
Verification branch: `verify/adaptive-recovery-runtime`

## Scope

Adaptive Recovery integration across T1–T9:

- ownership / unit foundation,
- execution generalization,
- registry/FSM/SHADOW,
- HedgeBundle smart split,
- virtual hedge TP / realized ledger / Core allocation,
- hedge lock / re-hedge,
- Continue-DCA / corridor / coverage,
- legacy exits / MoneyGuard / operator coordination,
- persistence / restart / ACTIVE wiring,
- native and Strategy Tester evidence.

## Current implementation state

The stacked feature chain contains all T1–T9 implementation slices. The verification branch is evidence-only above the exact T9 product source and does not intentionally alter trading semantics.

The source contains:

- separate Core and Recovery ownership domains,
- `RecoveryMode=OFF|SHADOW|ACTIVE`,
- independent BUY-Core and SELL-Core cycles,
- strict-reconcile execution metadata,
- exact integer-unit split logic,
- realized-only Recovery ledger,
- configurable Core close allocation,
- lock/re-hedge mechanics,
- state-aware DCA/corridor/coverage gates,
- exit/MoneyGuard coordination,
- dedicated versioned/checksummed Recovery persistence,
- startup reconciliation before ACTIVE automated mutation,
- ACTIVE scheduler wiring in Strategy.

## Evidence already present

- T1–T9 deterministic C++ model suites: PASS per slice.
- Sanitizer variants: PASS per slice where recorded.
- Exact-tree native MetaEditor compile through T9: 0 errors / 0 warnings with physical EX5.
- Existing BlackDragon native `RunTests.ex5`: 221 passed / 0 failed.
- Exact artifact SHA gating is recorded for the T9 native artifact.

## Critical evidence distinction

The 221/221 native `RunTests.mq5` suite is the existing BlackDragon regression suite. It does not directly contain Adaptive Recovery T1–T9 assertions.

Therefore it proves native regression compatibility for the compiled T9 tree, but it must not be reported as 221 Adaptive Recovery runtime assertions.

`RunRecoveryFoundationTests.mq5` exists and a broader native deterministic Recovery script is added on the verification branch so the Recovery pure rules can be compiled and executed inside real MQL5 runtime.

## Remaining runtime gaps

The following are not evidenced as PASS:

- Strategy Tester Recovery OFF golden A/B,
- one-direction ACTIVE lifecycle,
- split hedge lifecycle against tester positions/deals,
- simultaneous BUY/SELL Recovery cycles,
- Continue-DCA OFF/ON behavior in Strategy Tester,
- all four Core allocation modes in Strategy Tester,
- restart while Recovery broker state exists,
- delayed fill / reject / reconnect / history-sync ordering,
- SHADOW forward soak,
- ACTIVE demo soak,
- broker parity / forward evidence.

Current GitHub-hosted MT5 build stops Strategy Tester before execution because no terminal account context is available. This is `UNTESTABLE`, not EA PASS and not EA FAIL.

## Repository/integration state

The Adaptive Recovery stack remains outside `main`. PRs are stacked and open; the release level remains DRAFT.

Do not merge or promote based solely on compile/model/native legacy regression evidence if the intended release claim requires Strategy Tester or forward behavior.

## Documentation hygiene gap

The generic `SCAN_REPORT.md`, `RRI_REPORT.md`, and `BLUEPRINT.md` in this directory belong to earlier BD-001/BD-002 work. This task-specific SCAN avoids treating those older artefacts as Adaptive Recovery evidence.
