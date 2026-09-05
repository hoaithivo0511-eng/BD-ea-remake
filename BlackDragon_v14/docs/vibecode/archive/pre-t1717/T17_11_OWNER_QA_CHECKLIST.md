# T17.11 OWNER QA CHECKLIST

Use only the EX5 whose SHA256 matches the final PR evidence comment.

- Preserve the failing `20260826.log` environment: `.set`, symbol, timeframe, model, terminal build, account and margin mode.
- Fixture A: `HedgePartialClosePercent_=150` rejects init with zero trade/persistence mutation.
- Fixture B: BUY passive TP wait does not starve actionable SELL; repeat mirrored direction.
- Fixture C: max generation + Core>0 + Hedge=0 respects `ContinueDcaAfterHedge_`, does not request generation N+1, and does not loop on missing live-Hedge metrics.
- Fixture D: low-margin DCA produces bounded NO_MONEY attempts per bar; do not interpret this as stop-out protection.
- Fixture E: replay T17.9 REAL-TP interleave with no stale request, false reconcile or premature `TesterStop()`.
- Preserve tester/terminal logs, report and exact `.set` with hashes.

Strategy Tester is PASS only if the requested end date is reached, except the intentional invalid-init fixture. Forward/live remain ineligible without separate evidence and approval.

