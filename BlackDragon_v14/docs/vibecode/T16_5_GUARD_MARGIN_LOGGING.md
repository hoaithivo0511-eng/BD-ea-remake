# T16.5 — Guard Scope, Margin Capacity & Logging Discipline

Status: **DRAFT / owner Strategy Tester evidence required / DO NOT MERGE**.

T16.5 addresses the runtime findings discovered after T16.4. It does not change the approved ARCS TP-partial/Core-funding/stacked-generation semantics.

## 1. Guard valuation must match mutation scope

### Proven failure class

MoneyGuard previously evaluated Core-only BasketManager P/L while the Recovery exit coordinator could close both Core and `RecoveryMagic_` Hedge exposure.

A representative owner runtime incident was:

- Core-only PctDiff input: BUY `+6.45`, SELL `-2.19`, threshold `3.5%`.
- Core-only formula passed and requested close-all.
- The BUY-Core Recovery SELL Hedge carried roughly `-1466.60` floating P/L and was part of the coordinated mutation scope.
- Closing that omitted exposure caused a large realized balance loss.

### T16.5 contract

For MoneyGuard decisions while `RecoveryMode_=ACTIVE`:

- BUY economic side = Core BUY floating + SELL `RecoveryMagic_` Hedge floating owned by BUY Core.
- SELL economic side = Core SELL floating + BUY `RecoveryMagic_` Hedge floating owned by SELL Core.
- `MoneyTPAll`, `MoneySLAll`, PctDiff and side money TP/SL consume those economic side values.
- `MoneyTPAllAccount` remains whole-account `ACCOUNT_PROFIT` and is unchanged.
- The special hedged TP keeps its existing activation rule (both legacy Core baskets open), but its value is the economic Core+Recovery net.
- Daily economic net includes current Core/Recovery floating plus both Core and Recovery realized-today cash.
- If Recovery realized history cannot be seeded, only the Daily guard is deferred for that tick; account/floating guards remain available.

### Event-driven daily cache

Recovery realized-today history is not rescanned every tick.

- seed once at startup/first use and each server-day rollover;
- update from broker-confirmed Recovery deals;
- deal tickets are de-duplicated;
- floating Recovery positions remain live reads because floating P/L changes with price.

## 2. Deterministic capacity failure is WAIT, not RECONCILE

A local margin/volume preflight failure has no broker mutation and therefore does not imply unknown topology.

While an ARCS generation is `BUILDING`:

- insufficient free margin -> `CAPACITY_WAIT`;
- broker volume limit temporarily prevents the child -> `CAPACITY_WAIT`;
- explicit rejected OPEN with known no effect -> `CAPACITY_WAIT`;
- state remains BUILDING/ready and is retried later;
- Core DCA stays blocked while the generation remains incomplete;
- no false `RECONCILE_REQUIRED` and no tester stop from deterministic capacity alone.

The following still fail closed:

- ambiguous timeout/connection outcome;
- broker-observed volume above persisted target;
- execution journal requiring reconciliation;
- unknown/manual topology mutation.

## 3. Margin-aware DCA reserve

New input:

`RecoveryDcaMarginReserve_ = true`

Before a Core DCA that reaches or is beyond the Recovery threshold, T16.5 conservatively estimates margin for:

1. the proposed Core DCA; and
2. the next legal ARCS Hedge generation sized from projected post-DCA Core.

The DCA is deferred when current free margin cannot cover both estimates.

The reserve:

- is conservative and uses `OrderCalcMargin`;
- validates the projected Hedge bundle against broker volume min/max/limit;
- does not mutate state and never causes RECONCILE;
- does not force an otherwise legacy-compatible Recovery configuration into ARCS;
- is skipped when the current ARCS cycle has already reached `MaxHedgeGenerations_`, because no `Gmax+1` is legal.

## 4. Logging discipline

New input:

`RecoveryWaitLogSeconds_ = 900`

Meaning:

- expected Recovery waiting states emit the first diagnostic immediately;
- repeated heartbeat is at most once per configured interval;
- `0` means first occurrence only per key for that EA run;
- valid range `0..86400` seconds.

Global repeated `Log_Warn` throttle is changed from 60 seconds to 300 seconds.

Low-frequency heartbeat is used for:

- capacity wait;
- deferred positive-lock wait;
- max-generation/no-Hedge telemetry;
- max-order saturation;
- repeated exit-coordinator wait;
- DCA margin-reserve wait;
- repeated ACTIVE scheduler wait reason.

**Never suppress or batch away:**

- actual order submissions;
- fills/deals;
- partial closes;
- protective SL execution;
- explicit broker rejects;
- external/manual mutation;
- reconciliation transitions;
- errors;
- close-all lifecycle transitions.

Trade/audit lifecycle `INFO` and `ERROR` remain immediate.

## 5. Persistence semantics

`RecoveryDcaMarginReserve_` changes trading permission and is included in the T16 semantic fingerprint.

`RecoveryWaitLogSeconds_` changes telemetry only and is deliberately excluded from the semantic fingerprint.

## 6. Required verification

On one exact source tree:

1. all T1–T16.4 model/native regressions remain green;
2. T16.5 guard/margin/log pure model is green;
3. MetaEditor compiles all old targets, new T16.5 test and BlackDragon with 0 errors / 0 warnings;
4. T16.5 native script is green;
5. owner Strategy Tester replays the PctDiff+Recovery incident and proves the economic valuation does not trigger the old lossy close;
6. owner Strategy Tester reaches the prior insufficient-margin point and proves it stays in capacity wait rather than RECONCILE/TesterStop;
7. journal demonstrates reduced repeated waiting logs while order/fill/close/error evidence remains complete.

Until owner runtime evidence passes:

**DRAFT / NOT FORWARD_ELIGIBLE / NOT LIVE_ELIGIBLE / DO NOT MERGE**.
