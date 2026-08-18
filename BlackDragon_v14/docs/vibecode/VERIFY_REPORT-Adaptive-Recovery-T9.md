# VERIFY REPORT — Adaptive Recovery T9

Date: 2026-08-17 (Asia/Ho_Chi_Minh)  
Methodology: VibeCodeKit-MQL5 Full — VERIFY / EVIDENCE

## Source under verification

Current product source:

- Product branch: `feat/adaptive-recovery-t9-persistence-active`
- Product head: `0d7e20c1d024bb5d19a54128d3ddb3e346075235`
- Product tree: `89da566597ee98367b5ccdee5acc6c95a6e08002`
- Exact product native compile run: `32043966939`
- Compile job: `95428026318`
- PR compile merge ref: `2f6983080599fe6ca4d759823510d94aa33dfc36`
- Compile merge tree: `89da566597ee98367b5ccdee5acc6c95a6e08002`
- Product artifact: `mql5-build`, ID `9292469963`
- Product artifact ZIP SHA256: `f3389034aa861ce8eaa91e11d5c510585a82dc4ba93dc066f5ab1322810193e9`

The compile merge tree equals the product-head tree, so the Windows MetaEditor gate compiled the exact current product source.

Current verification source used for Recovery-specific native assertions:

- Verification branch: `verify/adaptive-recovery-runtime`
- Exact verification head: `adfa2740819fa8f11a0ab916ada1d241127c2fca`
- Exact verification tree: `f71c68a055d7cb96e1893d0f71ba76727bc8cdca`
- Recovery-native run: `32044044948`
- Recovery-native job: `95428229063`
- Evidence artifact: `mt5-recovery-native`, ID `9292476373`
- Evidence artifact ZIP SHA256: `03a1150edfeb708c2f8114392fb058c9d02b2d6ec11e56191a0431d78dccca5d`

The verification branch adds test/evidence workflows, test scripts and documentation. The only product-header defect discovered during this VERIFY cycle was propagated back to the T9 product branch before the final product compile.

## Defect found during VERIFY and fixed

Isolated native compilation of `RunRecoveryNativeTests.mq5` exposed a hidden include-order dependency:

- `RecoveryPersistence.mqh` uses `eExecCommandType`.
- The header did not directly include the declaration source `Types.mqh`.
- It compiled previously only when another include happened to provide that type first.

Fix:

```text
#include <BlackDragon/Types.mqh>
```

was added to `RecoveryPersistence.mqh` and documented as an explicit dependency.

This is a header self-containment fix; it does not alter Recovery trading semantics. After the fix, the current product tree was recompiled through the normal Windows MetaEditor gate and passed 0 errors / 0 warnings.

## Gate matrix

| Gate | Verdict | Evidence |
|---|---|---|
| T9 deterministic C++ model | PASS | Run `31966361472`, job `95212024330`: 117/117 regular + 117/117 ASan/UBSan |
| Current product MetaEditor compile | PASS | Run `32043966939`, job `95428026318`: `RunTests.mq5` 0/0; `BlackDragon.mq5` 0/0; physical EX5; exact tree `89da566...` |
| BlackDragon native regression | PASS | Run `32044230221`, job `95428717349`: **221 passed, 0 failed**, `ALL GREEN`; exact current product artifact `9292469963` SHA-gated |
| Recovery T1 native deterministic assertions | PASS | Run `32044044948`, job `95428229063`: **26 passed, 0 failed**, `ALL GREEN` |
| Recovery T3–T9 native deterministic assertions | PASS | Run `32044044948`, job `95428229063`: **106 passed, 0 failed**, `ALL GREEN` |
| Recovery native compile targets | PASS | `RunRecoveryFoundationTests` 0/0; `RunRecoveryNativeTests` 0/0; `BlackDragon` 0/0 |
| Strategy Tester launcher/config historical attempt | PASS to account gate | Hosted MT5 accepted `/config:` and reached Tester initialization before account prerequisite stopped execution |
| Strategy Tester / backtest | UNTESTABLE | No account-backed MT5 terminal context is available in current environment |
| Recovery OFF golden A/B | UNTESTABLE | Requires actual Strategy Tester execution |
| Recovery ACTIVE trade lifecycle | UNTESTABLE | Requires tester/broker positions and deals |
| Persistence/restart with broker state | UNTESTABLE | Requires account-backed positions/history across restart |
| Async delayed fill/reject/reconnect ordering | UNTESTABLE | No broker/tester runtime capable of exercising these events |
| SHADOW forward soak | UNTESTABLE | No connected demo environment supplied |
| ACTIVE demo soak / broker parity | UNTESTABLE | No connected demo environment supplied |
| Live | UNTESTABLE | Not attempted and must not be inferred |

## Evidence scope: three native assertion layers

### 1. Existing BlackDragon regression — 221/221

Workflow: `.github/workflows/verify-mt5-runtests.yml`

Current exact-product run:

- Run: `32044230221`
- Job: `95428717349`
- Product artifact reused: `9292469963`
- Required artifact SHA256: `f3389034aa861ce8eaa91e11d5c510585a82dc4ba93dc066f5ab1322810193e9`
- Extracted `RunTests.ex5`: 62976 bytes
- Native result: **221 passed / 0 failed**
- Evidence artifact: `mt5-native-runtests-current-t9`, ID `9292501605`
- Evidence artifact SHA256: `6c55b00821855878b993753a259e2ce7c5ee765f838a74ff032f57d56ec41510`
- Live trading: disabled.

Observed journal:

```text
BlackDragon v14 unit tests: 221 passed, 0 failed
ALL GREEN — safe to proceed to backtest comparison (golden baseline).
```

**Scope lock:** this is the existing BlackDragon regression suite. It is not the Adaptive Recovery assertion count.

### 2. Recovery T1 native assertions — 26/26

`RunRecoveryFoundationTests.mq5` was compiled and executed in a real MetaTrader 5 terminal:

```text
Recovery T1 foundation tests: 26 passed, 0 failed
ALL GREEN — T1 pure foundation behavior passed.
```

This closes the earlier T1 gap where the Recovery foundation script existed but had not been natively compiled/executed.

### 3. Recovery T3–T9 native deterministic assertions — 106/106

`RunRecoveryNativeTests.mq5` directly exercises deterministic MQL5 Recovery helpers covering:

- FSM transition legality and activation boundaries,
- coverage/corridor direction rules,
- exact integer-unit HedgeBundle split and exposure-deficit sizing,
- realized ledger and virtual TP math,
- partial-close planning and deterministic Core allocation,
- hedge-lock geometry and generation boundaries,
- Continue-DCA state/coverage/corridor gates,
- persistence hashes/tokens/state validation and pending-effect dedupe helpers.

Native result:

```text
Adaptive Recovery native tests: 106 passed, 0 failed
ALL GREEN — Adaptive Recovery T3-T9 deterministic MQL5 behavior passed.
```

Live trading was disabled. This evidence proves deterministic MQL5 rule execution; it does **not** substitute for Strategy Tester or broker lifecycle evidence.

## Strategy Tester attempts and external blocker

Historical workflow: `.github/workflows/verify-mt5-runtime.yml`

Prior attempts established the current GitHub-hosted MT5 limitation:

- Run `31980360705`: terminal accepted `/config:` but Tester stopped with `tester not started because the account is not specified`.
- Run `31980480759`, job `95246279099`: adding the documented `[Tester] Login=123456` example value still stopped at the same terminal-account prerequisite.

No broker/demo credential was available and none was fabricated.

The T9 source change made during the current VERIFY cycle is a header dependency declaration/self-containment fix. Repeating the same account-less hosted Strategy Tester workaround would not remove the external terminal-account prerequisite, so the higher runtime gates remain `UNTESTABLE`, not PASS and not EA FAIL.

## Evidence-bounded conclusion

### PASS

- T1–T9 implementation exists in the stacked product branches.
- T9 deterministic C++ model/sanitizer evidence.
- Current T9 product exact-tree MetaEditor compile: 0 errors / 0 warnings with physical EX5.
- Current-product BlackDragon regression: 221/221 native PASS.
- Recovery T1 native deterministic assertions: 26/26 PASS.
- Recovery T3–T9 native deterministic assertions: 106/106 PASS.
- Exact artifact SHA gating for current-product regression evidence.
- Hidden include-order dependency found and fixed, then recompiled/retested.

### UNTESTABLE in the current environment

- Recovery OFF Strategy Tester golden A/B.
- Actual ACTIVE Recovery trade lifecycle against tester/broker positions and deals.
- Smart-split child fill/reject/delayed-event lifecycle.
- Simultaneous BUY/SELL Recovery cycles in Strategy Tester.
- Continue-DCA OFF/ON behavioral matrix in Strategy Tester.
- Four Core allocation modes against actual tester deals.
- Persistence/restart while Core/Recovery broker state exists.
- Async delayed fills, reject, reconnect and history-sync fault injection.
- SHADOW forward soak.
- ACTIVE demo soak / broker parity.

These are not classified FAIL because the required account-backed runtime is unavailable.

## Release / integration gate

Release level remains **DRAFT**.

Do **not** claim `BACKTEST_ELIGIBLE`, `FORWARD_ELIGIBLE` or `LIVE_ELIGIBLE` from deterministic/native-script evidence alone.

The Adaptive Recovery stack remains outside `main`. Final integration/merge must not be represented as release completion while the contract-required Strategy Tester and forward gates remain unexecuted.

## Next material dependency

An authorized MetaTrader 5 environment with usable terminal/demo account context — for example a controlled self-hosted runner or supplied demo terminal environment — is required to continue the Strategy Tester, restart/reconnect and forward evidence ladder.
