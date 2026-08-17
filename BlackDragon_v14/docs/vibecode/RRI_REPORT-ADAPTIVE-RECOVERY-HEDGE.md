# RRI REPORT — Adaptive Recovery Hedge

Date: 2026-08-17 (Asia/Ho_Chi_Minh)  
Method: VibeCodeKit-MQL5 Full / RRI

## Decisions

| ID | Decision | Priority | Current status |
|---|---|---|---|
| AR-RRI-01 | Native `RunTests` 221/221 is BlackDragon regression evidence, not Adaptive Recovery assertion count. | P0 evidence integrity | LOCKED |
| AR-RRI-02 | Recovery OPEN timeout/restart must reconcile broker state/history before any resend. | P0 | IMPLEMENTED; broker runtime UNTESTABLE |
| AR-RRI-03 | Recovery tickets never enter legacy Core baskets or DCA indexing. | P0 | IMPLEMENTED; deterministic/native evidence PASS |
| AR-RRI-04 | Core exit/MoneyGuard/manual intervention cannot leave an unintended naked Recovery hedge. | P0 | IMPLEMENTED; Strategy Tester behavior UNTESTABLE |
| AR-RRI-05 | Startup ACTIVE remains blocked until persistence + broker/history reconciliation succeeds. | P0 | IMPLEMENTED; account-backed restart UNTESTABLE |
| AR-RRI-06 | Missing account-backed Strategy Tester evidence is `UNTESTABLE`; never infer behavior PASS. | P0 evidence integrity | LOCKED |
| AR-RRI-07 | Do not fabricate broker/demo credentials to turn an environment blocker green. | P0 safety | LOCKED |
| AR-RRI-08 | Recovery OFF must receive a golden A/B parity test before behavioral release claims. | P1 | UNTESTABLE in current environment |
| AR-RRI-09 | Forward promotion requires SHADOW soak before ACTIVE demo soak. | P1 | NOT EXECUTABLE in current environment |
| AR-RRI-10 | Integration into `main` must preserve the evidence boundary and current DRAFT release level until higher gates pass. | P1 | NOT MERGED |
| AR-RRI-11 | Recovery headers used as independent units must explicitly include their direct type dependencies. | P1 correctness | FIXED + native compile PASS |

## High-risk Q→A→R→P→T

### AR-D2-001 — duplicate non-idempotent hedge open

- Q: What if an OPEN request is accepted or filled but the expected callback is delayed/lost?
- A: Persist command identity and reconcile positions/deals before deciding the intended effect is absent.
- R: Never blind-retry unresolved Recovery OPEN.
- P: P0.
- T: Account-backed delayed-event/reconnect/restart scenarios; deterministic model tests are supporting evidence only.
- Current verdict: implementation/model/native deterministic evidence exists; actual broker timing remains `UNTESTABLE`.

### AR-D3-002 — restart during Recovery mutation

- Q: What if the terminal restarts in HEDGE_BUILDING / TP_PENDING / CORE_CLOSE_PENDING / LOCK_PENDING?
- A: Load versioned state, inspect broker/history truth, dedupe already-booked deals and already-filled children, then resume only when state is provably safe.
- R: Ambiguous mismatch => `RECONCILE_REQUIRED` / fail-closed.
- P: P0.
- T: Strategy Tester or authorized demo environment with positions/deals across restart.
- Current verdict: deterministic T9 suite PASS; account-backed restart remains `UNTESTABLE`.

### AR-D4-003 — ownership contamination

- Q: What if a Recovery child is counted by `CBasketManager` or contributes to legacy DCA index?
- A: RecoveryMagic remains a separate ownership domain and Recovery exposure is read separately.
- R: Core count/index must be based on legacy Core ownership only.
- P: P0.
- T: Static/model/native pure checks plus Strategy Tester basket/index trace.
- Current verdict: deterministic/native MQL5 layer PASS; Strategy Tester trace remains `UNTESTABLE`.

### AR-D5-004 — realized-credit accounting drift

- Q: What if planned hedge/Core close differs from actual fill volume or costs?
- A: Book only confirmed deal volume and `DEAL_PROFIT + DEAL_SWAP + DEAL_COMMISSION + DEAL_FEE` as applicable.
- R: Floating/planned profit is never spendable credit.
- P: P0/P1.
- T: Partial-fill and fee scenarios in model/native pure tests, then broker/tester confirmation.
- Current verdict: deterministic/native MQL5 ledger/planning assertions PASS; actual fill behavior remains `UNTESTABLE`.

### AR-D6-005 — Continue-DCA race

- Q: What if DCA and a Recovery mutation become eligible on the same tick?
- A: Recovery mutation/reconcile states are terminal/blocking; stable states may allow legacy DCA only under explicit policy.
- R: One mutation chain per cycle; `TryGridAdd` remains the Core DCA generator.
- P: P0.
- T: Native pure state-gate assertions plus Strategy Tester traces for OFF/ON.
- Current verdict: native deterministic state/coverage/corridor assertions PASS; Strategy Tester OFF/ON remains `UNTESTABLE`.

### AR-D7-006 — false evidence from native regression suite

- Q: Does 221/221 native `RunTests.ex5` prove T1–T9 Recovery behavior?
- A: No. It proves the existing BlackDragon regression script passes on the current T9 product artifact.
- R: Recovery-specific native assertions must be reported separately.
- P: P0 evidence integrity.
- T: Compile and execute `RunRecoveryFoundationTests` plus `RunRecoveryNativeTests` in real MT5 with live trading disabled.
- Current verdict: **CLOSED** — T1 26/26 PASS; T3–T9 106/106 PASS in native MT5, run `32044044948`.

### AR-D8-007 — hidden include-order dependency

- Q: What if a Recovery header only compiles because another include accidentally declares a required type first?
- A: Treat each directly testable header dependency as explicit; isolated native test compilation must not depend on unrelated include order.
- R: `RecoveryPersistence.mqh` must directly include `Types.mqh` because it stores `eExecCommandType`.
- P: P1 correctness/toolchain robustness.
- T: Compile the Recovery-specific native script that includes persistence directly, then compile the full product exact tree.
- Current verdict: **CLOSED** — defect found by VERIFY, fixed on T9 branch, Recovery-native compile PASS and current product MetaEditor compile 0/0.

## Evidence now closed at native deterministic layer

- Current product exact-tree MetaEditor compile: PASS, run `32043966939`.
- Current-product BlackDragon regression: 221/221 PASS, run `32044230221`.
- Recovery T1 native deterministic assertions: 26/26 PASS, run `32044044948`.
- Recovery T3–T9 native deterministic assertions: 106/106 PASS, run `32044044948`.

## Required remaining gate order

1. Recovery OFF golden A/B Strategy Tester.
2. ACTIVE Strategy Tester scenario matrix.
3. Restart/reconnect/async broker-state evidence.
4. SHADOW forward soak.
5. ACTIVE demo soak / broker parity.
6. Only then consider forward/live promotion.

All remaining gates require account-backed MetaTrader infrastructure unavailable to the current GitHub-hosted environment. A lower gate cannot substitute for a higher gate.
