# RRI REPORT — BD-001 / BD-002

## Decisions

| ID | Decision | Example |
|---|---|---|
| D-001 | Any close intent is terminal for the current tick. | BUY hits SL and DCA at the same price: send close only; do not send DCA. |
| D-002 | Simultaneous BUY and SELL exit decisions may both send close requests before the tick returns. | Both baskets hit an exit on one tick: close both, then stop. |
| D-003 | A pending close blocks new opens and SL/TP modifies until reconciliation. | Close callback is delayed: following ticks perform no entry/modify work. |
| D-004 | REQUEST accepted is not completion. | REQUEST→DEAL and DEAL→REQUEST must produce the same single logical completion. |
| D-005 | First request latency is unchanged. | The initial open/close is sent immediately; only duplicates are suppressed. |
| D-006 | Lost-event recovery is conservative. | Reconcile observed state first; retain the lock to a hard timeout before releasing with a warning. |

## Q→A→R→P→T

### BD-D2-001

- Q: What if a close and DCA are both true on one tick?
- A: Close wins and ends the tick.
- R: No open or modify intent may occur after any close intent.
- P: P0
- T: Model the simultaneous conditions and assert the trace contains only
  close intents.

### BD-D2-002

- Q: What if REQUEST arrives before DEAL/POSITION?
- A: Keep the journal active and the busy/pending guard locked.
- R: REQUEST accepted advances lifecycle state but does not complete it.
- P: P0
- T: Run REQUEST→DEAL and DEAL→REQUEST permutations and assert one completion.

### BD-D7-003

- Q: What if no final callback is observed?
- A: Reconcile broker state; keep a working order locked; release only at the
  hard timeout with a warning.
- R: Recovery must not create an immediate duplicate request.
- P: P0
- T: Exercise soft timeout, live-order wait, reconciled state and hard timeout.

