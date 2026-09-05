# T17.9 Owner Strategy Tester Handoff

Use only `BlackDragon.ex5` whose SHA256 matches the exact-head `PROVENANCE.txt` in the final T17.9 artifact.

- Confirm PR #28 is still Draft and its HEAD equals provenance HEAD.
- Re-run the REAL-TP interleave setup: 4 same-side Core positions, common broker TP, Core Pyramid/new Core simultaneously eligible.
- Confirm zero new same-side Core/Pyramid order enters the settling cohort.
- Confirm every old broker TP is logged as expected, with no external/manual latch.
- Confirm no stale `ModifySlTp(position=0)`, `RECONCILE_REQUIRED`, `TesterStop()` or unexpected stop.
- Confirm a clean later campaign can start after settlement.
- Attach tester configuration, complete journal/log, report and hashes to PR #28.

MetaEditor/native PASS is not Strategy Tester PASS. Until this owner run is attached, Strategy Tester and release eligibility remain `UNTESTABLE`/false.
