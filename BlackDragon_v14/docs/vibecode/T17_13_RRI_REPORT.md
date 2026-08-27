# T17.13 RRI REPORT

## Risk-ranked invariants

1. **P0 mutation serialization:** Recovery/Overlap broker mutation or reconcile state admits no Core open intent in the same tick.
2. **P0 owner switch:** read-only Recovery concurrency exists only when `ContinueDcaAfterHedge_=true`.
3. **P1 soft pre-leg ownership:** a candidate with no broker mutation does not starve same-side Core growth.
4. **P1 live denominator:** admitted Core growth rebases Hedge target from current exact Core units while existing caps remain authoritative.
5. **P1 provenance:** owner tests only the EX5 whose commit/tree/hash match the final Windows job.

## Numeric oracle

- BUY trigger: `4091.635 - 13.0 * 0.10 = 4090.335`; ask `4049.197 <= 4090.335`, therefore spacing is due.
- Hedge target: floor(`26 * 120%`) = `31` units; after Core becomes `33`, floor(`33 * 120%`) = `39` units.
- Exact allowed path: Recovery `HEDGE_BUILDING`, continuation true, no Recovery mutation, Overlap `PAIR_ARMED`, no pending execution, spacing due => one open intent.
- Negative mirrors change one boundary at a time and require zero open intents.

## Triggered guards

`RETRO-A1`, `A2`, `A3`, `A4`, `A5`, `A6`, `A8`, `A9`, `A10` and `A12` are enforced by the contract. P0 guards are non-waivable for forward/live eligibility.
