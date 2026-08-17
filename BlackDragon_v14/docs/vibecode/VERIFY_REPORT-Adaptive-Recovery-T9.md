# VERIFY REPORT — Adaptive Recovery T9

Date: 2026-08-17 (Asia/Ho_Chi_Minh)
Methodology: VibeCodeKit-MQL5 Full — VERIFY / EVIDENCE

## Source under verification

- Product branch: `feat/adaptive-recovery-t9-persistence-active`
- Product head: `1d323c2afcc213dcd6eaaa296eb71a20788a8de9`
- Product tree: `f73b0daefea96f4300ea89bca68f28ac19ccc4b3`
- Native build artifact: `mql5-build`, ID `9268636368`
- Artifact ZIP SHA256: `30de810bab53a8078c61b9653c20f99e8b285be50b153dbaf1d5fae82b8e12bf`
- `BlackDragon.ex5` from that artifact: 272490 bytes
- `RunTests.ex5` from that artifact: 62864 bytes

Verification branch is evidence-only. Comparing T9 head to the VERIFY branch before this report showed only `.github/workflows/verify-mt5-runtime.yml` and `.github/workflows/verify-mt5-runtests.yml`; no product `.mq5`, `.mqh`, `.set`, or trading logic changed.

## Gate matrix

| Gate | Verdict | Evidence |
|---|---|---|
| T9 deterministic C++ model | PASS | Run `31966361472`, job `95212024330`: 117/117 regular and 117/117 ASan+UBSan |
| Native MetaEditor compile | PASS | Run `31966480439`, job `95212302452`: RunTests 0/0; BlackDragon 0/0; physical EX5 |
| Native MQL5 RunTests execution | PASS | Run `31980612807`, job `95246600350`: **221 passed, 0 failed**, `ALL GREEN` |
| Exact EX5 provenance for native runtime | PASS | Runtime job re-downloaded artifact `9268636368` and rejected it unless ZIP SHA256 matched exact T9 build digest |
| Strategy Tester launcher syntax/config | PASS to account gate | Terminal build 6116 loaded the generated `/config:` file and started Tester initialization |
| Strategy Tester / backtest | UNTESTABLE | Hosted terminal stops before test: `tester not started because the account is not specified` |
| T9 persistence restart with broker positions/history | UNTESTABLE | Requires a Strategy Tester or terminal account context capable of positions/deals across restart |
| Async broker fill/reject/reconnect ordering | UNTESTABLE | No account-backed broker/tester runtime in current hosted environment |
| Forward demo soak | UNTESTABLE | No connected demo account/environment supplied |
| Live | UNTESTABLE | Not attempted; no live claim |

## Native RunTests execution

Workflow: `.github/workflows/verify-mt5-runtests.yml`

The workflow:

1. Installs a fresh MetaTrader 5 terminal on Windows Server 2025.
2. Downloads GitHub Actions artifact ID `9268636368` from the final T9 native compile.
3. Computes SHA256 of the downloaded ZIP and requires exact equality with `30de810bab53a8078c61b9653c20f99e8b285be50b153dbaf1d5fae82b8e12bf`.
4. Extracts the exact `RunTests.ex5` (62864 bytes) from that artifact.
5. Executes it in MetaTrader 5 through `[StartUp] Script=BlackDragon\Tests\RunTests` with `ShutdownTerminal=1`.
6. Parses the native MQL5 journal and fails unless the summary exists, failed assertions are zero, passed assertions are positive, and the `ALL GREEN` marker exists.

Observed native MQL5 journal:

```text
RunTests (EURUSD,M1) BlackDragon v14 unit tests: 221 passed, 0 failed
RunTests (EURUSD,M1) ALL GREEN — safe to proceed to backtest comparison (golden baseline).
```

Run: `31980612807`
Job: `95246600350`
Evidence artifact: `mt5-native-runtests`, ID `9272236350`
Evidence artifact ZIP SHA256: `30547d12e5de212e35fcdb023dd2dd568c2c6b6a6aa7ed3efa14871e1c7a6e7a`

This closes the previous evidence gap where `RunTests.mq5` had only been compiled but not executed.

## Strategy Tester attempts and blocker

Workflow: `.github/workflows/verify-mt5-runtime.yml`

The smoke matrix reuses the exact T9 `BlackDragon.ex5` artifact and attempts:

1. Recovery OFF smoke.
2. Recovery ACTIVE smoke with VERIFY-only aggressive trigger inputs (`RecoveryStartAfterDca_=0`, `HedgeGapPips_=0`, `HedgeTPPips_=0`) to maximize the chance of reaching Recovery state transitions if Core entries occur.

No product source or release `.set` is changed by this harness.

### Attempt 1 — harness parse defect

Run `31980274962` never launched Strategy Tester because a PowerShell interpolation string used `$name:`. This is a VERIFY harness defect only and provides no EA runtime verdict.

### Attempt 2 — account context gate

Run `31980360705`, job `95246002257`:

- MT5 install: PASS
- exact T9 artifact SHA gate: PASS
- generated tester parameter sets: PASS
- terminal accepted the `/config:` file
- Tester stopped with: `tester not started because the account is not specified`

### Attempt 3 — official `[Tester] Login` supplied

Run `31980480759`, job `95246279099` added `Login=123456`, matching the MetaTrader documentation example for the emulated tester account number.

Result remained:

```text
Tester tester not started because the account is not specified
Terminal tester didn't start
```

Therefore the current MetaTrader 5 build 6116 on a clean GitHub-hosted runner requires terminal account context beyond the emulated `[Tester] Login` value before this backtest can start. No real/demo account credentials are available in the environment, and no credentials were fabricated.

Evidence artifact for attempt 3: `mt5-runtime-smoke`, ID `9272205030`, SHA256 `292873043c1977affbc81ec8514ca1c83adc212802d68da50bcc81be30b5dae2`.

## Evidence-bounded conclusion

### PASS

- T1–T9 implementation evidence already recorded in their stacked PRs.
- Final T9 native MetaEditor compile 0 errors / 0 warnings and physical EX5.
- T9 deterministic model/sanitizer suite.
- Native MetaTrader execution of the exact T9 `RunTests.ex5`: **221/221 PASS**.
- Exact artifact provenance for that runtime execution.

### UNTESTABLE in current environment

- Actual Strategy Tester backtest.
- Recovery ACTIVE trade lifecycle against broker/tester positions and deals.
- Persistence/restart recovery while Recovery hedge/Core positions exist.
- Async delayed fills, broker reject, reconnect and history-sync fault injection.
- Forward/demo soak.

These items are not classified FAIL because the EA never reached Strategy Tester execution; the environment stopped at the missing terminal-account prerequisite.

## Release gate

Release level remains **DRAFT**.

Do **not** claim `BACKTEST_ELIGIBLE`, `FORWARD_ELIGIBLE`, or `LIVE_ELIGIBLE` from the current evidence. The next material gate requires an MT5 environment with a usable terminal/demo account context (or an equivalent authorized self-hosted runner) so Strategy Tester and restart scenarios can execute for real.
