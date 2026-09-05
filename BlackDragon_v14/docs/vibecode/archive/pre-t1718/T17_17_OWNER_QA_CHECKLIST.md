# T17.17 Owner Strategy Tester QA

Use only the `BlackDragon.ex5` whose SHA256 and size match `PROVENANCE.txt` in the final T17.17 owner-QA artifact.

- Reuse the supplied run's symbol, period, model and `.set`, including `RecoveryMode_=2`, Overlap during Recovery, `HedgeSLMode_=SL_BROKER`, `CoreCloseMode_=2` and `MoneyTPAllAccount=100`.
- Preserve complete tester/terminal Journal logs, `.set`, HTML/XML report, terminal build, account type/deposit/leverage and EX5 SHA256.
- Confirm exact ARCS broker SLs during an active Overlap Recovery-route cycle log as expected and do not create external/manual Recovery reconciliation.
- Confirm unknown/manual close evidence remains fail-closed.
- Confirm MoneyTP account close reaches flat, logs Recovery global finalization, clears obsolete Overlap RECONCILE and does not reopen on the completion tick.
- Confirm trading evaluation resumes on later ticks and the tester reaches its configured end date without repeated Overlap reconcile warnings.
- Run a restart/resume case with `RecoveryTesterResumeState_=true` to verify durable reset; run normal tester isolation with it false.

MetaEditor/native PASS is not Strategy Tester PASS. Forward/live and merge remain disabled until owner evidence is attached and approved.

