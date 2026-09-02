# T17.14 RETRO — Deferred trade callbacks and terminal guard liveness

## Repeated failure pattern

Synchronous trade effects may become visible inside an initiating call before MT5 delivers the corresponding `OnTradeTransaction` callbacks. A validator that compares broker state against persisted ownership during that window can create a false permanent reconcile hold even though exact history proof already exists.

A terminal account risk guard must not wait behind a narrower reconcile hold. Detection priority alone is insufficient; the actual close dispatch must also preempt narrower work and its begin operation must be idempotent across ticks.

## Permanent guards

- Before validating persisted ownership after a synchronous mutation, replay only exact identity-bound broker effects that are already in history.
- Replay must require the complete volume delta, reject increases/partial proof and be idempotent under callback permutation.
- Ownership refresh must not duplicate cash/cursor accounting performed by normal deal callbacks.
- Account-wide close-to-flat is a terminal boundary above side-specific Recovery/Overlap work; repeated begin calls must not reset the flatten epoch.
- Native compile and deterministic callback models remain QA inputs; owner Strategy Tester is an independent gate.

## Open gate

`Strategy Tester=PENDING_OWNER_RERUN`; release, forward and live eligibility remain false.
