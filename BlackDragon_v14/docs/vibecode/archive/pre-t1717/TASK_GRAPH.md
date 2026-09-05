# TASK GRAPH — BD-001 / BD-002

```text
TIP-001 Close-terminal coordinator
    ↓
TIP-002 Async lifecycle state machine
    ↓
TIP-003 Regression tests and static contracts
    ↓
TIP-004 VERIFY, retro and package
```

TIP-001 precedes TIP-002 so no new open can race an in-flight close. TIP-003
tests both event orders independently of production callbacks. TIP-004 may not
declare READY while MT5 compile and async demo soak remain unexecuted.

