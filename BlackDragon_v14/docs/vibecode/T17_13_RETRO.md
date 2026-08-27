# T17.13 RETRO — Concurrency ownership and evidence

## Current outcome

The approved implementation separates read-only policy ownership from broker-mutation ownership. The verification correction adds an independent scheduler oracle with an execution spy and makes legacy source contracts explicitly recognize the T17.13 supersession instead of pinning obsolete wrapper names.

## Permanent guards

- A read-only component may defer its own work but cannot consume unrelated same-side progress.
- A broker mutation, pending close/protection action or reconciliation state remains exclusive.
- A compatibility source contract must assert current semantic composition, not a superseded filename or wrapper token.
- Exact-HEAD native compilation and an EX5 hash are QA inputs only; owner Strategy Tester evidence remains an independent gate.

## Open gate

`Strategy Tester=PENDING_OWNER`; release, forward and live eligibility remain false until evidence is bound to the exact reviewed build.
