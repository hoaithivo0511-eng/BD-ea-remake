# PROJECT STATE — Adaptive Recovery Hedge

Date: 2026-08-17 (Asia/Ho_Chi_Minh)  
Methodology: VibeCodeKit-MQL5 Full  
Phase: VERIFY / EVIDENCE  
Release level: **DRAFT**

## Canonical product source

- Repository: `hoaithivo0511-eng/BD-ea-remake`
- Base line: BlackDragon v14.9
- T9 product branch: `feat/adaptive-recovery-t9-persistence-active`
- Product head: `0d7e20c1d024bb5d19a54128d3ddb3e346075235`
- Product tree: `89da566597ee98367b5ccdee5acc6c95a6e08002`
- Product is not merged into `main`.

## Methodology progress

| Phase / task | Status |
|---|---|
| SCAN | DONE — task-specific Adaptive Recovery scan exists |
| RRI | DONE for currently available evidence; account-backed risks remain runtime-gated |
| SPECIFY | DONE |
| DECIDE | DONE |
| CONTRACT | DONE |
| PLAN / TASK GRAPH | DONE |
| BUILD T1–T9 | DONE implementation |
| Native deterministic/model verification | PASS |
| Exact-tree native MetaEditor compile | PASS |
| Native Recovery-specific deterministic MQL5 assertions | PASS |
| Strategy Tester behavioral verification | UNTESTABLE — missing terminal account context |
| Restart/reconnect/broker-state verification | UNTESTABLE — missing account-backed runtime |
| SHADOW forward soak | UNTESTABLE — no demo environment supplied |
| ACTIVE demo / broker parity | UNTESTABLE — no demo environment supplied |
| Integration into `main` | NOT DONE — intentionally release-gated |
| Forward/live promotion | NOT ELIGIBLE |

## Current PASS evidence

### Product compile

- Run `32043966939`
- Job `95428026318`
- Exact product tree: `89da566597ee98367b5ccdee5acc6c95a6e08002`
- `RunTests.mq5`: 0 errors / 0 warnings
- `BlackDragon.mq5`: 0 errors / 0 warnings
- Artifact `mql5-build`: ID `9292469963`
- Artifact SHA256: `f3389034aa861ce8eaa91e11d5c510585a82dc4ba93dc066f5ab1322810193e9`

### Current-product native BlackDragon regression

- Run `32044230221`
- Job `95428717349`
- Product artifact SHA-gated before execution
- Result: 221 passed / 0 failed, `ALL GREEN`
- Evidence artifact ID `9292501605`
- Evidence artifact SHA256 `6c55b00821855878b993753a259e2ce7c5ee765f838a74ff032f57d56ec41510`
- Scope: existing BlackDragon regression suite, not Adaptive Recovery assertion count.

### Recovery-specific native MQL5 deterministic verification

- Run `32044044948`
- Job `95428229063`
- T1 foundation: 26 passed / 0 failed
- T3–T9 deterministic Recovery assertions: 106 passed / 0 failed
- All Recovery native compile targets: 0 errors / 0 warnings
- Evidence artifact ID `9292476373`
- Evidence artifact SHA256 `03a1150edfeb708c2f8114392fb058c9d02b2d6ec11e56191a0431d78dccca5d`
- Live trading disabled.

### T9 deterministic model

- Run `31966361472`
- Job `95212024330`
- Regular: 117/117 PASS
- ASan + UBSan: 117/117 PASS

## Defect closed during VERIFY

`RecoveryPersistence.mqh` had a hidden include-order dependency on `eExecCommandType`. The header now explicitly includes `Types.mqh`. The fix is on the T9 product branch and was included in the exact product compile PASS above.

## Remaining external-runtime gates

These tasks are still required by the Full contract but cannot execute with the currently available GitHub-hosted terminal:

1. Recovery OFF golden A/B Strategy Tester comparison.
2. One-direction ACTIVE Recovery lifecycle.
3. Smart-split child fill/reject/delayed-event lifecycle.
4. Parallel BUY-Core / SELL-Core Recovery cycles.
5. Continue-DCA OFF/ON Strategy Tester behavior.
6. All four Core close allocation modes against actual tester deals.
7. Restart during critical Recovery pending states with broker positions/history.
8. Delayed fills, reject, reconnect and history-sync ordering.
9. SHADOW forward demo soak.
10. ACTIVE low-risk demo soak and broker-specific volume/tick/stops/freeze parity.

Prior hosted Strategy Tester attempts stopped before test execution with:

```text
tester not started because the account is not specified
```

Providing the documented example `[Tester] Login=123456` did not satisfy the terminal-account prerequisite. No real/demo credential is available through the current environment and none was fabricated.

## Stop / release rule

Current work is **implementation-complete but not Full-release-complete**.

Do not:

- infer Strategy Tester PASS from native scripts,
- infer restart/broker parity from deterministic tests,
- merge and describe the result as release-ready,
- claim `BACKTEST_ELIGIBLE`, `FORWARD_ELIGIBLE` or `LIVE_ELIGIBLE`,
- enable live trading.

## Next material dependency

To continue the Full evidence ladder, provide or connect an authorized MT5 environment with usable terminal/demo account context, ideally a controlled self-hosted runner capable of Strategy Tester execution and restart/reconnect scenarios.
