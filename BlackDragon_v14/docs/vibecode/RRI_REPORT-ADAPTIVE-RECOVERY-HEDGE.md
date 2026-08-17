# RRI REPORT — Adaptive Recovery Hedge

Date: 2026-08-17 (Asia/Ho_Chi_Minh)  
Method: VibeCodeKit-MQL5 Full / RRI

## Decisions

| ID | Decision | Priority |
|---|---|---|
| AR-RRI-01 | Native `RunTests` 221/221 is BlackDragon regression evidence, not Adaptive Recovery assertion count. | P0 evidence integrity |
| AR-RRI-02 | Recovery OPEN timeout/restart must reconcile broker state/history before any resend. | P0 |
| AR-RRI-03 | Recovery tickets never enter legacy Core baskets or DCA indexing. | P0 |
| AR-RRI-04 | Core exit/MoneyGuard/manual intervention cannot leave an unintended naked Recovery hedge. | P0 |
| AR-RRI-05 | Startup ACTIVE remains blocked until persistence + broker/history reconciliation succeeds. | P0 |
| AR-RRI-06 | Missing account-backed Strategy Tester evidence is `UNTESTABLE`; never infer behavior PASS. | P0 evidence integrity |
| AR-RRI-07 | Do not fabricate broker/demo credentials to turn an environment blocker green. | P0 safety |
| AR-RRI-08 | Recovery OFF must receive a golden A/B parity test before behavioral release claims. | P1 |
| AR-RRI-09 | Forward promotion requires SHADOW soak before ACTIVE demo soak. | P1 |
| AR-RRI-10 | Integration into `main` must preserve the evidence boundary and current DRAFT release level until higher gates pass. | P1 |

## High-risk Q→A→R→P→T

### AR-D2-001 — duplicate non-idempotent hedge open

- Q: What if an OPEN request is accepted or filled but the expected callback is delayed/lost?
- A: Persist command identity and reconcile positions/deals before deciding the intended effect is absent.
- R: Never blind-retry unresolved Recovery OPEN.
- P: P0.
- T: Account-backed delayed-event/reconnect/restart scenarios; deterministic model tests are supporting evidence only.

### AR-D3-002 — restart during Recovery mutation

- Q: What if the terminal restarts in HEDGE_BUILDING / TP_PENDING / CORE_CLOSE_PENDING / LOCK_PENDING?
- A: Load versioned state, inspect broker/history truth, dedupe already-booked deals and already-filled children, then resume only when state is provably safe.
- R: Ambiguous mismatch => `RECONCILE_REQUIRED` / fail-closed.
- P: P0.
- T: Strategy Tester or authorized demo environment with positions/deals across restart.

### AR-D4-003 — ownership contamination

- Q: What if a Recovery child is counted by `CBasketManager` or contributes to legacy DCA index?
- A: RecoveryMagic remains a separate ownership domain and Recovery exposure is read separately.
- R: Core count/index must be based on legacy Core ownership only.
- P: P0.
- T: Static/model/native pure checks plus Strategy Tester basket/index trace.

### AR-D5-004 — realized-credit accounting drift

- Q: What if planned hedge/Core close differs from actual fill volume or costs?
- A: Book only confirmed deal volume and `DEAL_PROFIT + DEAL_SWAP + DEAL_COMMISSION + DEAL_FEE` as applicable.
- R: Floating/planned profit is never spendable credit.
- P: P0/P1.
- T: Partial-fill and fee scenarios in model/native pure tests, then broker/tester confirmation.

### AR-D6-005 — Continue-DCA race

- Q: What if DCA and a Recovery mutation become eligible on the same tick?
- A: Recovery mutation/reconcile states are terminal/blocking; stable states may allow legacy DCA only under explicit policy.
- R: One mutation chain per cycle; `TryGridAdd` remains the Core DCA generator.
- P: P0.
- T: Native pure state-gate assertions plus Strategy Tester traces for OFF/ON.

### AR-D7-006 — false evidence from native regression suite

- Q: Does 221/221 native `RunTests.ex5` prove T1–T9 Recovery behavior?
- A: No. It proves the legacy/current BlackDragon regression script passes on the T9 compiled tree.
- R: Recovery-specific native assertions must be reported separately.
- P: P0 evidence integrity.
- T: Compile and execute `RunRecoveryFoundationTests` plus the dedicated `RunRecoveryNativeTests` script in real MT5 with live trading disabled.

## Required gate order

1. Deterministic/model + sanitizer.
2. Exact-source native MetaEditor compile.
3. Native MQL5 Recovery-specific deterministic assertions.
4. Recovery OFF golden A/B Strategy Tester.
5. ACTIVE Strategy Tester scenario matrix.
6. Restart/reconnect/async broker-state evidence.
7. SHADOW forward soak.
8. ACTIVE demo soak / broker parity.
9. Only then consider forward/live promotion.

A lower gate cannot substitute for a higher gate.
