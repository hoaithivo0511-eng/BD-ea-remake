# T17.14 RRI REPORT

## Risk-ranked invariants

1. **P0 exact proof:** persisted 134 units, live 0 and exactly 134 proven protective-close units refresh ownership to zero; 133 or 135 proof units must fail.
2. **P0 idempotency:** repeating the same refresh/callback after ownership reaches live volume is a no-op and never re-consumes cash.
3. **P0 fail-closed negative:** live volume above persisted, unknown identity, manual close or missing history remains reconciliation-required.
4. **P0 risk liveness:** account guard reaches existing global flatten even when an Overlap/reconcile cycle reports blocking work.
5. **P1 ordering:** pending OPEN is resolved before contradictory close; side/Magic/Daily guards retain their existing coordinator behavior.
6. **P1 provenance:** the owner tests only EX5 whose commit/tree/hash match the Windows-native artifact.

## Triggered guards

`RETRO-A1`, `A2`, `A3`, `A4`, `A5`, `A6`, `A8`, `A9`, `A10` and `A12` are enforced by the contract. P0 guards are non-waivable for forward/live eligibility.
