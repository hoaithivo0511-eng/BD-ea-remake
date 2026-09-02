# T17.16 Owner Strategy Tester QA

Use only the EX5 whose SHA256 matches the final `PROVENANCE.txt`.

- Reuse the attached failing `.set` and full requested interval; record terminal build, broker, symbol, M1, real-tick model and delay.
- Confirm the tested EX5 filename/size/SHA256 matches the handoff.
- At every `Hedge target ... mới=` increase, verify no Recovery child opens until new-bar/MinuteStop, favorable gap and `HedgePyramidLockBeforeAdd_` all allow it.
- Confirm true broker-split children of one admitted stage can finish without an artificial second-stage delay.
- Reproduce economics-safe `HEDGE_BUILDING` Overlap; verify Core denominator, retained Hedge hard cap and current generation target refresh before ladder continuation.
- After any `NO_MONEY`, confirm DCA, Core Pyramid and Recovery OPEN all remain blocked across later bars until the logged `reopenAt` Free Margin threshold is reached.
- Confirm closes/Overlap/risk reductions remain operable during capacity embargo.
- Confirm no `RECONCILE_REQUIRED`, unexpected `TesterStop`, hard-cap violation or account stopout.
- Confirm tester reaches the requested end date; attach complete log, `.set`, HTML/XML report and hashes.

Native compile/unit PASS is not Strategy Tester PASS. PR #28 remains Draft and forward/live remain ineligible until this checklist has owner evidence.
