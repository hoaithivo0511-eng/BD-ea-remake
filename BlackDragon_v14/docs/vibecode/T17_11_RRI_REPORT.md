# T17.11 RRI REPORT

## Risk-ranked invariants

1. **P0 scheduler liveness:** passive direction A cannot own direction B's progress.
2. **P0 state truth:** terminal no-Hedge is derived from authoritative phase/generation/Core/Hedge facts, not a log string or renumbered enum.
3. **P1 fail-fast configuration:** every existing Recovery validator is composed before runtime mutation.
4. **P1 admission idempotency:** one identical `NO_MONEY` DCA payload is admitted at most once per bar unless the intent or capacity materially changes.

## Numeric examples

- BUY `ACTIVE`, live/opened/remaining=`70/70/70`, TP not hit; SELL `ARMED`, gap hit: SELL is evaluated in the same scheduler tick.
- phase=`ARCS_LOCKED`, generation=`5`, max=`5`, Core=`100` units, Hedge=`0`: terminalNoHedge=true.
- the same zero-Hedge facts at generation `4/5` or phase `ARCS_ACTIVE`: terminalNoHedge=false and Hedge-dependent gates remain fail-closed.
- DCA BUY index `6`, normalized lot `0.24`, bar `1000`: after `NO_MONEY`, ticks in bar `1000` are blocked; bar `1060`, lot `0.20`, or free margin reaching the recorded required margin may admit one new attempt.

## Triggered Retro Guards

| Guard | Severity | Enforcement |
| --- | --- | --- |
| RETRO-A1 state/order | P0 | mirror-direction and terminal-boundary tests |
| RETRO-A2 runtime failure | P0 | fail-fast config and fail-closed missing-Hedge tests |
| RETRO-A3 approved decision | P1 | contract/source invariants |
| RETRO-A4 independent oracle | P1 | standalone C++ model |
| RETRO-A5 cached capacity | P1 | stale/same-bar and release tests |
| RETRO-A6 async side effects | P0 | raw retcode disposition and duplicate suppression tests |
| RETRO-A8 retry event | P0 | latch persists until bar/intent/capacity change |
| RETRO-A9 units | P0 | T17.10 exact regression unchanged |
| RETRO-A12 multi-file | P1 | source contract and exact-head compile |

All P0 guards are non-waivable for forward/live eligibility.

