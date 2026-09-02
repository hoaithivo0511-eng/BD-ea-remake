# T17.8 OWNER STRATEGY TESTER QA

Status: TEST BUILD / PR DRAFT / DO NOT MERGE UNTIL OWNER TESTER PASS.

## Scope locked

T17.8 fixes only the two P1 defects reproduced by the latest owner Strategy Tester log:

1. Recovery `ARCS_ACTIVE` after final Hedge stage must not persist/no-op on every tick and must not starve Core DCA/Pyramid while Hedge TP is still waiting.
2. Core broker REAL TP (`DEAL_REASON_TP`) that matches the EA-programmed side TP cohort must not be classified as manual/external mutation. Before Recovery owns the side it bypasses safely; after ownership it becomes a durable full-side coordinated cleanup epoch.

## Explicitly NOT changed

- `HedgePyramidCoverageSequence_` semantics remain T17.7/T17.5 canonical ascending TOTAL coverage targets.
- No change to `ArraySort(work)` / de-dup / hard-cap handling in `Pyramid_NormalizeCoverageTargetsPure`.
- No change to Hedge gap mapping, add-only rule, final target or absolute cap semantics.

## Required owner Strategy Tester scenarios

### A. Reproduce previous Hedge starvation run

Use the same `.set` family and market period that previously reached final Hedge coverage around 150% then appeared frozen.

PASS requires:
- final Hedge stage can transition `BUILDING -> ACTIVE`;
- while Hedge TP is not hit, journal shows a throttled Vietnamese wait such as `Hedge đã đủ target, TP chưa đạt | DCA/Pyramid tiếp tục được xét`;
- Strategy continues evaluating Core Pyramid and DCA;
- no per-tick persistence storm / no tester freeze;
- `ContinueDcaAfterHedge_=true` can reach its normal coverage/corridor gates;
- no unexpected RECONCILE / TesterStop / no-money / stopout;
- tester reaches requested end date.

### B. Reproduce previous REAL TP failure

Set `TP_Mode=REAL` and use the same configuration that previously stopped around the first broker TP cohort.

PASS requires:
- broker `DEAL_REASON_TP` on exact Core Magic with the EA-programmed common TP does NOT log `external/manual close changed ARCS Core/Hedge topology`;
- before Recovery ownership, TP cohort closes without ARCS fail-closed;
- when Recovery owns the side, TP starts `TP THẬT ... Recovery dọn side theo chu kỳ an toàn` and closes/cleans Core/Hedge deterministically;
- restart/resume with `RecoveryTesterResumeState_=true` can reload an active REAL-TP epoch and continue cleanup;
- manual/unknown close identity still remains fail-closed;
- no TesterStop caused by expected REAL TP;
- tester reaches requested end date.

## Evidence to preserve

- exact EX5 SHA256 and source HEAD/TREE from `PROVENANCE.txt`;
- `.set` file;
- tester + terminal Journal logs;
- HTML/XML Strategy Tester report;
- terminal build, symbol, timeframe, model, execution delay, account type/deposit/leverage;
- screenshots only as supplemental evidence, not as a replacement for logs/report.

Forward/live remains NOT ELIGIBLE until these owner Strategy Tester cases pass.
