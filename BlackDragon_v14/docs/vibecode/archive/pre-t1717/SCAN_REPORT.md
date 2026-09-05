# SCAN REPORT — BD-001 / BD-002

Date: 2026-07-28

## Scope

- `Include/BlackDragon/Strategy.mqh`
- `Include/BlackDragon/ExecutionLayer.mqh`
- `Include/BlackDragon/Types.mqh`
- `Experts/BlackDragon/BlackDragon.mq5`
- `Scripts/BlackDragon/Tests/RunTests.mq5`
- `Scripts/BlackDragon/Tests/offline_suite.cpp`

## Current behavior

- Strategy orders panel actions, guard, exits, entries and real-level changes in
  one `OnTick` call without a terminal close result.
- Async requests enter a journal, but an accepted
  `TRADE_TRANSACTION_REQUEST` immediately deactivates the entry.
- Busy-open and pending-close/modify guards therefore end before the resulting
  deal/order/position state is guaranteed to be observable.

## Existing invariants to preserve

- Only `ExecutionLayer` calls `OrderSend`/`OrderSendAsync`.
- Only `Panel` touches chart objects.
- Async remains the live/demo default; tester remains synchronous.
- No `Sleep`, no blocking wait and no change to lot, DCA, exit or signal
  formulas.
- Panel manual orders continue to bypass an already-active daily halt, but a
  newly triggered risk close is terminal for that tick.

## Gaps

- No close-terminal contract in the coordinator.
- No persistent accepted/final/observed lifecycle in the async journal.
- No event-order permutation tests for REQUEST/DEAL/POSITION.
- Existing watchdog can release a request after five seconds without a final
  observable state.

