# T17.19 RRI Report

Risk tier: P1 execution/persistence; Vibecode Full.

| Risk | Guard | Locked response |
|---|---|---|
| Child SL looks positive while total chain is negative | A1/A4 | Sum all used layers' realized Recovery cash; require nonnegative aggregate |
| Manual/external close arms re-entry | A2/A5 | Require exact persisted protective target plus broker/virtual ownership proof |
| Reopen occurs in the SL callback or price chatter | A1/A6 | Persist WAIT_RESET, require favorable buffer, then ARMED return crossing on a later drive |
| Crash between trigger and G1 | A6/A8 | Persist TRIGGER_PENDING before resetting/starting the ARCS generation book |
| Old persistence layout changes | A1/A7 | Keep ARCS v4 untouched; use a separate atomic T17.19 v1 record |
| Pip/tick geometry reverses by direction | A4/A9 | Independent tick-space BUY/SELL boundary tests |
| DCA-only owner amendment accidentally blocks Pyramid | A3/A12 | Separate DCA and Pyramid-ADD admission APIs and exact source call-site checks |
| EXHAUSTED blocks exits | A2/A12 | Gate ADD only; never skip Pyramid Drive/Peel or close paths |
| Re-entry uses stale Core volume | A5 | Reset to G1, then let current Hedge Pyramid scheduler recompute from broker Core |
| C++ differs from MQL/Windows/VPS | A10 | Matching C++/native tests, exact-head GitHub compile, conditional hash-bound tunnel run |

Residual risk: broker gaps can fill beyond the programmed anchor, margin may be
insufficient for the first new Hedge stage, and uncapped Core Pyramid settings
can still increase exposure during WAIT_RESET/ARMED by explicit owner choice.
