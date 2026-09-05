# CONTRACT — BD-001 / BD-002

## Deliverables

1. Close-terminal coordinator behavior.
2. Event-order-independent async journal.
3. MQL-side pure lifecycle tests.
4. Offline lifecycle, permutation, timeout and coordinator tests.
5. Updated architecture, changelog and handoff notes.
6. Verify and completion reports.

## Acceptance criteria

- No open/modify after a close intent in the same tick.
- Pending close blocks subsequent entry/modify work.
- REQUEST accepted alone does not release busy/pending guards.
- REQUEST→DEAL and DEAL→REQUEST both complete exactly once.
- Rejected request releases immediately.
- Soft timeout keeps unresolved requests locked.
- Hard timeout releases with reconciliation warning.
- Existing offline suite remains green.
- UBSan remains green.
- No trade API call moves outside `ExecutionLayer`.

## Exclusions

- BD-003 and later findings.
- Lot/DCA/signal/exit formula changes.
- Netting support.
- MetaTrader compilation or broker soak that cannot run in this environment.

