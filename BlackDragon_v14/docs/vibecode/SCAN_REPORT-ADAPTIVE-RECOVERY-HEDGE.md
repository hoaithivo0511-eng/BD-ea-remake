# SCAN REPORT — Adaptive Recovery Hedge

Date: 2026-08-17 (Asia/Ho_Chi_Minh)  
Method: VibeCodeKit-MQL5 Full / SCAN  
Product implementation head: `0d7e20c1d024bb5d19a54128d3ddb3e346075235`  
Product tree: `89da566597ee98367b5ccdee5acc6c95a6e08002`  
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

The stacked feature chain contains all T1–T9 implementation slices. Product source remains outside `main` and release level remains DRAFT.

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

## Current evidence

- T1–T9 deterministic C++ model suites: PASS per recorded slice.
- Sanitizer variants: PASS where recorded.
- T9 deterministic persistence model: 117/117 regular + 117/117 ASan/UBSan.
- Current product exact-tree MetaEditor compile: PASS, `RunTests.mq5` 0 errors / 0 warnings and `BlackDragon.mq5` 0 errors / 0 warnings, run `32043966939`.
- Current product artifact: ID `9292469963`, SHA256 `f3389034aa861ce8eaa91e11d5c510585a82dc4ba93dc066f5ab1322810193e9`.
- Existing BlackDragon native regression on the current product artifact: 221/221 PASS, run `32044230221`.
- Recovery T1 native MQL5 deterministic assertions: 26/26 PASS, run `32044044948`.
- Recovery T3–T9 native MQL5 deterministic assertions: 106/106 PASS, run `32044044948`.
- Recovery-native evidence artifact: ID `9292476373`, SHA256 `03a1150edfeb708c2f8114392fb058c9d02b2d6ec11e56191a0431d78dccca5d`.

## VERIFY finding closed

Isolated compilation of the new Recovery-native script found that `RecoveryPersistence.mqh` referenced `eExecCommandType` without directly including `Types.mqh`.

This hidden include-order dependency was fixed by making the header self-contained. The fix was propagated to the T9 product branch and the exact current product tree was recompiled 0/0 before evidence was accepted.

## Evidence distinction

The 221/221 native `RunTests.mq5` suite is the existing BlackDragon regression suite. It proves regression compatibility on the current T9 compiled artifact, not 221 Adaptive Recovery assertions.

Adaptive Recovery-specific deterministic native evidence is reported separately:

- T1: 26/26.
- T3–T9: 106/106.

These native scripts execute deterministic rules in real MetaTrader 5 with live trading disabled. They do not emulate or replace Strategy Tester/broker lifecycle evidence.

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

Current GitHub-hosted MT5 stops Strategy Tester before execution because no terminal account context is available. This is `UNTESTABLE`, not EA PASS and not EA FAIL. No broker/demo credentials were fabricated.

## Repository/integration state

The Adaptive Recovery stack remains outside `main`. PRs are stacked and open. Do not represent the current deterministic/native-script evidence as backtest, forward or live readiness.

## Documentation hygiene

The generic `SCAN_REPORT.md`, `RRI_REPORT.md`, and `BLUEPRINT.md` in this directory belong to earlier BD-001/BD-002 work. This task-specific SCAN is the canonical Adaptive Recovery scan record.
