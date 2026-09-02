# T17.15 SCAN — Overlap capability during Hedge build

Baseline: `eb9b963cab1ba996f23adf23fa9fe2a366e94fc3`, tree `4bd0a542957b80492ca6e6012320f2ad70a04e74`.

Owner log `20260828.log` contains 223 economics-safe Overlap candidates that passed reserve checks but were deferred while Recovery reported `HEDGE_BUILDING`. The state-only policy treated the entire build phase as mutation-active even when the Recovery durable command, execution journal and exit coordinator were quiet.

Affected runtime path:

1. Overlap arms an economics-safe pair.
2. `RouteForSide` classifies Recovery ownership.
3. Recovery exit coordinator persists and submits each Core close.
4. Broker-confirmed trim changes the exact-Core denominator.
5. ARCS validates the live book and continues the Hedge ladder.

Risk: P0/P1 order lifecycle and recovery topology. Full mode is mandatory. Native compile and owner Strategy Tester remain independent gates.
