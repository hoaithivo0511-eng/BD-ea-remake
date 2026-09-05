# T15 — Recovery Persistence Isolation / Semantic Identity

Status: **DRAFT — owner-approved fix scope, verification in progress**  
Method: VibeCodeKit-MQL5 **Full** / SCAN → RRI → SPECIFY → DECIDE → CONTRACT → PLAN → BUILD → VERIFY → EVIDENCE → RETRO  
Base: T14 HEAD `4abcaae4b7a9c3acacc25d839987880622ebed00`  
Branch: `feat/recovery-t15-persistence-isolation`

## Incident

A Strategy Tester run using Recovery ACTIVE remained unable to open Core #1 and repeatedly printed:

```text
new Core series blocked: Recovery ACTIVE is not reconciled/ready
```

Source audit proved the entry gate was behaving fail-closed because `CRecoveryEngine::ActiveReady()` remained false after startup reconciliation. The durable Recovery filename was scoped only by symbol/account/CoreMagic/RecoveryMagic and could therefore be reused by later Strategy Tester passes. The payload identity checked only a subset of Recovery semantics (`RecoveryStartAfterDca_` plus broker/account identity), allowing a persisted FSM snapshot to be interpreted under changed Hedge TP/partial-close/lock/re-hedge/DCA policy.

Triggered guards:

- `RETRO-A2` — explicit runtime failure policy.
- `RETRO-A3` — owner-approved Recovery semantics must remain locked.
- `RETRO-A7` — persisted test state requires isolated environment/reset proof.
- `RETRO-A12` — multi-file edit requires exact-target post-edit verification.

## Owner-approved decisions

### D-T15-01 — Strategy Tester starts Recovery persistence clean by default

Add:

```cpp
input bool RecoveryTesterResumeState_ = false;
```

Policy:

- live/forward runtime always reuses Recovery persistence exactly as before;
- Strategy Tester with `false` treats prior Recovery persistence as absent and bootstraps a fresh pass;
- Strategy Tester with `true` deliberately reuses persistence for restart/reconciliation QA.

This is isolation, not deletion: the next valid save replaces the normal durable file. No live account durability is weakened.

### D-T15-02 — Persisted Recovery state is bound to the complete Recovery semantic policy

Persistence schema version is raised from `1` to `2` and stores a deterministic `semanticConfigHash` over:

1. `RecoveryMode_`
2. `RecoveryMagic_`
3. `RecoveryStartAfterDca_`
4. `HedgeGapPips_`
5. `HedgeTPPips_`
6. `HedgePartialClosePercent_`
7. `CoreCloseMode_`
8. `HedgeLockNetProfitPips_`
9. `HedgeLockSafetyBufferPips_`
10. `ReHedgeGapPips_`
11. `MaxHedgeGenerations_`
12. `ContinueDcaAfterHedge_`
13. `MinHedgeCoveragePercent_`
14. `TargetRecoveryCorridorPips_`

`RecoveryTesterResumeState_` is deliberately excluded because it controls QA persistence reuse, not trading semantics.

Any semantic mismatch remains fail-closed. A v1 file is not silently migrated into v2 live state.

### D-T15-03 — Invalid tester evidence stops early

When Strategy Tester reaches the automated new-series or DCA gate while Recovery ACTIVE is still not ready, the pass calls `TesterStop()` after emitting an explicit error. Live/forward runtime remains running/fail-closed so higher-scope MoneyGuard/exit handling is not disabled by an initialization abort.

## Contract

Allowed paths:

- `BlackDragon_v14/Include/BlackDragon/Recovery/RecoveryTypes.mqh`
- `BlackDragon_v14/Include/BlackDragon/Recovery/RecoveryPersistence.mqh`
- `BlackDragon_v14/Include/BlackDragon/Recovery/RecoveryDca.mqh`
- `BlackDragon_v14/Scripts/BlackDragon/Tests/recovery_t9_persistence_suite.cpp`
- this T15 document

Forbidden semantic changes:

- no change to Recovery hedge sizing;
- no change to ARMED/HEDGE/TP/Core-close/lock/re-hedge state transitions;
- no change to T14 execution-identity proof;
- no change to live persistence reuse policy other than schema identity becoming stricter;
- no merge to `main` before native compile and owner Strategy Tester evidence.

## Acceptance matrix

| Gate | Required result |
|---|---|
| C++ Recovery persistence model | PASS, including tester isolation + mutation of every semantic fingerprint field |
| Existing model/static suites | PASS |
| Exact-tree MetaEditor | `RunTests`, `RunRecoveryMutationTests`, `RunRecoveryIdentityTests`, `BlackDragon` = 0 errors / 0 warnings |
| Existing native MT5 scripts | legacy 246/0; T13 mutation 26/0; T14 identity 17/0 |
| Fresh Strategy Tester pass | no inherited Recovery state; `ACTIVE startup reconciliation complete`; Core #1 can open when signal/filters permit |
| Intentional restart QA | `RecoveryTesterResumeState_=true`; persisted state must reconcile or fail-closed with explicit reason |
| Semantic mismatch QA | changed Recovery semantic input must not resume an old snapshot |

## Release boundary

Until owner runtime evidence is supplied:

- DRAFT
- NOT BACKTEST_ELIGIBLE
- NOT FORWARD_ELIGIBLE
- NOT LIVE_ELIGIBLE
- DO NOT MERGE MAIN

T15 fixes persistence/test isolation only. It does not by itself close the separate T14 Strategy Tester execution-identity release gate.