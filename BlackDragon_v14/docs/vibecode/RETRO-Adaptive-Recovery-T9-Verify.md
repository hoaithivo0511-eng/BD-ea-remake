# RETRO — Adaptive Recovery T9 VERIFY

Date: 2026-08-17 (Asia/Ho_Chi_Minh)

## What passed

- T9 deterministic C++ model remained PASS: 117/117 regular + 117/117 ASan/UBSan.
- Current product head `0d7e20c1d024bb5d19a54128d3ddb3e346075235`, tree `89da566597ee98367b5ccdee5acc6c95a6e08002`, compiled in Windows MetaEditor with `RunTests.mq5` 0 errors / 0 warnings and `BlackDragon.mq5` 0 errors / 0 warnings.
- Current product artifact `9292469963` was SHA-gated as `f3389034aa861ce8eaa91e11d5c510585a82dc4ba93dc066f5ab1322810193e9` before native regression execution.
- Existing BlackDragon regression suite executed from that exact current-product artifact and returned 221 passed / 0 failed.
- `RunRecoveryFoundationTests.mq5` was compiled and executed in native MT5: 26 passed / 0 failed.
- New `RunRecoveryNativeTests.mq5` was compiled and executed in native MT5: 106 passed / 0 failed across deterministic T3–T9 Recovery rules.
- Live trading and DLL import were disabled for native script verification.
- Artifact SHA gating prevented accidental reuse of stale or rebuilt EX5 evidence.

## Defect found and closed

Recovery-specific isolated compilation exposed a hidden include-order dependency:

- `RecoveryPersistence.mqh` stored `eExecCommandType` but did not directly include `Types.mqh`.
- Previous full-product include order happened to make the type visible, hiding the dependency.
- The header was made self-contained by explicitly including `Types.mqh`.
- The fix was propagated to the T9 product branch, then the exact current product tree was recompiled 0/0.

This validates the value of compiling narrower native test surfaces instead of relying only on a monolithic product include graph.

## Evidence correction retained

The native **221/221** result belongs to the existing BlackDragon regression suite. It must not be described as 221 Adaptive Recovery assertions.

Adaptive Recovery-specific native deterministic evidence is:

- T1: **26/26 PASS**.
- T3–T9: **106/106 PASS**.

## What did not become testable

- GitHub-hosted MetaTrader 5 build 6116 still lacks the terminal account context required to start Strategy Tester.
- A previous attempt using the documented `[Tester] Login=123456` example did not satisfy that platform prerequisite.
- Therefore Recovery OFF golden A/B, ACTIVE backtest lifecycle, broker-state restart, async execution timing, forward/demo behavior and broker parity remain `UNTESTABLE` in this environment.

## Process corrections retained

1. Do not classify CI/harness defects as EA FAIL.
2. Do not fabricate demo/broker credentials to make a tester gate green.
3. Bind every native runtime claim to an exact product artifact digest.
4. Distinguish legacy regression assertions from subsystem-specific assertions.
5. Compile subsystem test surfaces independently enough to expose hidden header dependencies.
6. Propagate any real product fix found during VERIFY back to the product branch, then re-run the exact product compile gate.
7. Stop opening redundant environment workarounds once the remaining blocker requires external account capability.
8. Keep release at DRAFT until actual Strategy Tester and forward evidence exist.

## Next material dependency

An authorized MT5 environment with usable terminal/demo account context — for example a controlled self-hosted runner or supplied demo terminal environment — is required before continuing the account-backed Strategy Tester, restart/reconnect and forward evidence matrix.
