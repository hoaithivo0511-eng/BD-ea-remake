# T17.15 Owner Strategy Tester QA

Use only the exact-head `BlackDragon.ex5` whose SHA-256 matches `PROVENANCE.txt`.

Re-run the same `.set`, symbol, M1 period and date range that produced `20260828.log`.

PASS evidence must show:

- an economics-safe Overlap candidate during a journal-quiet `HEDGE_BUILDING` phase is locked and executes through the coordinated Recovery route;
- if a request/durable journal/coordinator mutation is pending, the candidate defers with zero duplicate request;
- the preflight never permits retained Hedge above the configured effective hard cap after projected Core trim;
- after broker-confirmed trim, log shows `T17.15 post-Overlap target refresh` with refreshed Core, retained/live Hedge and new target;
- when the refreshed target exceeds live generation volume, later valid ladder conditions can open the remaining child;
- no unexpected `RECONCILE_REQUIRED`, duplicate close/open, `TesterStop`, no-money storm or stopout;
- the tester reaches its requested end date.

Attach `.set`, complete tester/terminal logs, report, terminal build, symbol/timeframe/model/execution delay/deposit/leverage and file hashes. Forward/live and merge remain blocked until owner evidence is reviewed.
