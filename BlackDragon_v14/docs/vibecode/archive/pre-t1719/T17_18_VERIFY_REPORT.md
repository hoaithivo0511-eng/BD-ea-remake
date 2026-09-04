# T17.18 Verify Report

## Local deterministic gate

Status: `PASS`.

Evidence:

- T17.18 dashboard-free source contract: 15 passed / 0 failed;
- repository/include/version/workflow contract: 9 passed / 0 failed;
- established C++ model regression: 37/37 suites PASS;
- source contracts T17.11–T17.18: 8/8 PASS;
- JSON/YAML parse and `git diff --check`: PASS;
- deep review Stage 0–7: 107 files, 1,140 grounded packets,
  `critical=4,error=55,warn=334,info=29`, still `release-blocked`;
- previous cleanup baseline was `4/56/338/29`: no new aggregate severity;
- deep-review JSON SHA256:
  `4a654ad9efac4cff02c8612f1e12274da0b274981b600d4ea8c2aa2b219f10a6`;
- deep-review Markdown SHA256:
  `c4fae7aab451a6cdaae7df8fc9c8e89e4bde69afb1614d50735ed3d366a9e311`.

The new `UX-04` detector item on `WmfSignalOverlay.mqh` is a reviewed false
positive: the module uses the stable `BD_WMF_OBJ_PREFIX`, calls
`ObjectsDeleteAll` during eligible init/deinit, caps arrows at 200 and is
disabled in non-visual tester mode. It is an arrow-only overlay, not a panel.

## Exact-head Windows gate

Status: `PENDING_REMOTE_COMMIT`.

Required:

- exact repository/HEAD/tree/run/numeric jobs/Windows/toolchain provenance;
- ProbeEA, full EA and all 27 native scripts compile 0 errors/0 warnings;
- 27/27 native suites, expected aggregate 915 passed/0 failed;
- `blackdragon-current-owner-qa` artifact and direct EX5 SHA256/size.

This task changes chart-control availability and public input surface but not
automatic trading semantics. Owner Strategy Tester remains `PENDING_OWNER`;
forward/live/release remain false and PR #28 remains Draft.
