# BLUEPRINT — Safe close boundary and idempotent async lifecycle

## Objective

Remove BD-001 and BD-002 without changing strategy formulas or the latency of
the first trade request.

## Coordinator design

1. Consume both panel close requests.
2. If a panel close was requested, return from the tick.
3. If any close is already pending, return from the tick.
4. Evaluate the widest-scope money guard; if it produces an action, return.
5. Evaluate both basket exits; allow both sides to close, then return if either
   produced an exit.
6. Only then process manual opens, automated entries and real levels.

## Async state design

`SENT → REQUEST_ACCEPTED → OBSERVED/COMPLETED`

- Rejected REQUEST completes as failed and releases its guard.
- Accepted REQUEST records server order/deal ids and final-volume information.
- DEAL/ORDER/POSITION events may arrive before or after REQUEST.
- Completion is driven by observed deal volume, resulting position state,
  desired SL/TP state or order deletion.
- Watchdog reconciles state at the soft timeout and releases only at a separate
  hard timeout if no broker evidence remains.

## Performance budget

- No `Sleep` or synchronous polling.
- No additional work on ordinary ticks except one bounded journal scan for
  `HasAnyPendingClose`.
- Position scans occur on request/event/watchdog paths, not inside formula hot
  loops.
- Initial `OrderSendAsync` call remains in the same decision tick.

