# Adaptive Recovery T9 — VERIFY Gate Status

- Product source: `0d7e20c1d024bb5d19a54128d3ddb3e346075235`
- Product tree: `89da566597ee98367b5ccdee5acc6c95a6e08002`
- T9 deterministic model: **PASS** — 117/117 regular + 117/117 ASan/UBSan
- Current product native MetaEditor: **PASS** — `RunTests.mq5` 0/0; `BlackDragon.mq5` 0/0; physical EX5; run `32043966939`
- Current-product BlackDragon regression: **PASS** — 221/221, `ALL GREEN`; run `32044230221`; product artifact `9292469963` SHA-gated
- Recovery T1 native deterministic assertions: **PASS** — 26/26, `ALL GREEN`; run `32044044948`
- Recovery T3–T9 native deterministic assertions: **PASS** — 106/106, `ALL GREEN`; run `32044044948`
- Header self-containment gate: **PASS after fix** — `RecoveryPersistence.mqh` now directly includes `Types.mqh`; exact product recompile 0/0
- Strategy Tester/backtest: **UNTESTABLE** — current GitHub-hosted MT5 requires terminal account context before test execution
- Recovery OFF golden A/B: **UNTESTABLE**
- ACTIVE broker/tester lifecycle: **UNTESTABLE**
- Persistence/restart with broker state: **UNTESTABLE**
- Async fill/reject/reconnect: **UNTESTABLE**
- SHADOW forward demo: **UNTESTABLE**
- ACTIVE demo / broker parity: **UNTESTABLE**
- Live: **UNTESTABLE / NOT ATTEMPTED**
- Integration into `main`: **NOT DONE** — stack remains open and release-gated
- Release level: **DRAFT**

The 221/221 suite is BlackDragon regression evidence; Adaptive Recovery-specific native evidence is reported separately as 26/26 T1 and 106/106 T3–T9.

See `VERIFY_REPORT-Adaptive-Recovery-T9.md` for provenance, artifact hashes and evidence limits.
