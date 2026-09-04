# Current Version — BlackDragon

| Layer | Canonical value |
|---|---|
| Product/binary | `15.00` |
| Runtime lineage | `T17.20` |
| Entry point | `Experts/BlackDragon/BlackDragon.mq5` |
| Dashboard/buttons | Removed |
| WMF signal arrows | Preserved; controlled by `ShowWmfSignals` |
| Terminal RH re-entry | Exact positive chain BE/SL; 2 cycles by default |
| Optional RH bar gate | `RecoveryOneOrderPerBar_=false`; one opening per chart candle/direction when enabled |
| Branch / PR | `feat/t17-full-pyramid` / #28 Draft |
| Owner Strategy Tester | `PENDING_OWNER` |

`BlackDragon_v14` remains an installation/path compatibility directory; it is
not the product version. Versioned Base/T17 headers are live composition layers
when reachable, not duplicate EA binaries. Historical specifications are frozen
under `docs/vibecode/archive/`.

The current entry point must reach every tracked runtime header. CI requires one
canonical workflow, every model/native suite, source contracts T17.11–T17.20,
MetaEditor 0 errors/0 warnings, native 972/0 and exact artifact provenance.

The T17.19 chart remains dashboard-free, not visualization-free: optional WMF
arrows remain separate. WAIT_RESET/ARMED blocks Core DCA but deliberately leaves
Core Pyramid ADD settings-driven. No Strategy Tester, forward or live claim
follows from source/native verification.
