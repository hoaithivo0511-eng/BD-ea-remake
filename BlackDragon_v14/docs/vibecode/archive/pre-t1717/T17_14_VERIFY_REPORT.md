# T17.14 VERIFY REPORT

## Local deterministic verification

- Baseline: `e8b5a301db148c9aa797cdfa0772270125d5e036` / tree `24a53f2d19c99178e02ea0332ebb689957304be0`.
- T17.14 independent model: `12 passed / 0 failed`.
- T17.14 source contract: `10 passed / 0 failed`.
- T17.11–T17.13 source contracts: PASS.
- Full established C++ model regression: `34 suites`, PASS.
- YAML/JSON parse and `git diff --check`: PASS.
- Runtime Retro initializer: PASS; generated guard records remain `UNTESTABLE` until exact-head hashes are attached.
- Generic root-layout contract/retro checker: `UNTESTABLE` for this repository because canonical T17 artefacts live under `docs/vibecode/` rather than duplicate root filenames.
- Draft root-EA lint: PASS with four non-blocking legacy warnings unrelated to T17.14.

## Runtime boundaries

- Local MetaEditor/native MT5: `UNTESTABLE` on this host; required Windows GitHub job is configured.
- Owner Strategy Tester: `PENDING` on the new exact-head EX5.
- Forward/live: `NOT_ELIGIBLE`.

Windows compile, native matrix, EX5 hash/size and artifact provenance are intentionally recorded by the exact-head workflow rather than pre-written into repository evidence.
