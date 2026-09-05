# T17.15 RRI

## Locked owner answers

- Replace state-only admission with a capability gate.
- Permit `HEDGE_BUILDING` only when Recovery is ready and no durable Recovery command, execution-journal mutation, or coordinator obligation is pending.
- Before any Core trim, project the exact-Core denominator and reject the pair if all retained Recovery Hedge would exceed the configured effective hard cap.
- After broker-confirmed trim, recompute exact Core, live Hedge and the current BUILDING target; persist the refreshed target before the next ladder add.

## Numeric oracle

- Core before: 100 units; intended trim: 20; refreshed Core: 80.
- Prior retained Hedge: 50; current generation live: 18; total retained Hedge: 68.
- Hard cap/final coverage: 90%; maximum total Hedge: 72.
- Refreshed current-generation target: `72 - 50 = 22`; ladder may add four units.
- If projected Core were 70, cap would be 63 and the same 68 Hedge must block before mutation.

## Fail policy

Missing readiness, any unresolved mutation, inconsistent denominator, failed persistence, or post-trim cap violation is fail-closed. The fix never auto-closes Hedge and never weakens ambiguous-outcome reconciliation.
