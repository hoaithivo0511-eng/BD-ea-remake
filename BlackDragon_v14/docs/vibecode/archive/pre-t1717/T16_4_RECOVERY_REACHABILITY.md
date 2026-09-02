# T16.4 — Recovery Reachability + Saturation Observability

Status: **DRAFT / owner Strategy Tester verification only / DO NOT MERGE**.

## Runtime incident

Owner Strategy Tester evidence showed a long period with no new DCA, Hedge or Overlap mutation. The effective configuration was:

- `MaxOrdersBuy=8`
- `MaxOrdersSell=8`
- `RecoveryStartAfterDca_=13`
- `OverlapOrderNumber=6`
- `RecoveryMode_=ACTIVE`

The approved Recovery threshold semantic is current-open Core count:

`Recovery DCA count = Core open count - 1`

Therefore `RecoveryStartAfterDca_=13` requires **14 currently-open Core positions**. With `MaxOrders=8`, Recovery could never arm. The EA previously accepted this mathematically unreachable ACTIVE configuration and later stopped DCA silently at `MaxOrders`.

## T16.4 contract

### 1. ACTIVE reachability is a startup invariant

For each enabled side:

`requiredCore = RecoveryStartAfterDca_ + 1`

ACTIVE is valid only when:

- BUY enabled: `requiredCore <= MaxOrdersBuy`
- SELL enabled: `requiredCore <= MaxOrdersSell`

Violation is `INIT_PARAMETERS_INCORRECT` through the existing Recovery init path. OFF and SHADOW remain permissive/observational.

Examples:

- MaxOrders=8, StartAfterDca=7 -> reachable.
- MaxOrders=8, StartAfterDca=8 -> invalid.
- MaxOrders=8, StartAfterDca=13 -> invalid.
- A disabled side does not invalidate ACTIVE because it cannot be expected to create that Core chain.

### 2. Semantic is NOT changed to cumulative DCA

T16.4 does not reinterpret `RecoveryStartAfterDca_`. It still counts currently-open Core positions minus the initial order. Changing to cumulative DCA requires a separate owner decision because Overlap can close the threshold ticket and would require a durable historical anchor policy.

### 3. Overlap-before-Recovery is visible

If `Overlap=true` and:

`OverlapOrderNumber < RecoveryStartAfterDca_ + 1`

T16.4 logs a warning that Overlap may trim the current-open Core count before Recovery reaches its threshold. This is intentionally warning-only; it does not disable Overlap and does not change the Recovery trigger.

### 4. MaxOrders saturation is no longer silent

When a side reaches its configured MaxOrders under ACTIVE Recovery, T16.4 emits throttled telemetry containing:

- side/direction;
- current Core count;
- MaxOrders;
- RecoveryStartAfterDca;
- required Core count;
- whether the threshold is reachable under that MaxOrders ceiling;
- current ARCS phase.

The existing DCA generation path is unchanged: no extra Core order is opened beyond MaxOrders.

## Unchanged semantics

T16.4 does not change:

- T16 stacked Hedge sizing;
- Hedge TP/partial-close funding ledger;
- Broker/Virtual SL;
- T16.1 protective-SL event ordering;
- T16.2 deterministic SL reject handling;
- T16.2 Overlap-after-Hedge mutation order/refresh;
- T16.3 deferred-lock yield;
- T16.3 MAXED_NO_HEDGE behavior;
- `MaxHedgeGenerations_` ceiling;
- persistence schema v4.

## Required verification

Exact-tree deterministic gates:

1. all existing model suites remain green;
2. new T16.4 reachability model suite = 20/0;
3. MetaEditor compiles the new native script and BlackDragon with 0 errors / 0 warnings;
4. native `RunRecoveryReachabilityTests` = 20/0;
5. legacy/T13/T14/T16.2/T16.3 native gates remain green.

Owner runtime gates:

1. Loading the previously failing `MaxOrders=8 / StartAfterDca=13` ACTIVE set must fail initialization clearly as unreachable; it must not start a long invalid pass.
2. A corrected reachable set such as `MaxOrders=8 / StartAfterDca<=7` must initialize and can exercise Recovery normally.
3. When Core reaches MaxOrders, Journal must show the T16.4 saturation diagnostic instead of going silent.
4. If Overlap starts before the Recovery threshold, Journal must show the cross-policy warning.

Until owner runtime evidence passes: **DRAFT / NOT FORWARD_ELIGIBLE / NOT LIVE_ELIGIBLE / DO NOT MERGE**.
