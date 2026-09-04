# T17.19 Verify Report

Status: implementation complete; exact-head CI and owner QA remain open.

| Gate | Status |
|---|---|
| Independent T17.19 C++ model | PASS — 33/33 |
| Native T17.19 MQL suite | PENDING exact-head Windows matrix |
| T17.19 source contract | PASS — 17/17 |
| Established 37 C++ suites | PASS — 37/37; 38/38 including T17.19 |
| Source contracts T17.11–T17.18 | PASS — 8/8; T17.11–T17.19 all PASS |
| Repository contract | PASS — 9/9 |
| Deep review | COMPLETE — baseline critical/error unchanged; see evidence below |
| Exact branch-head MetaEditor full compile | PENDING |
| Complete native matrix | PENDING |
| TunnelVibemq5 MT5-2 compile/test | PASS with bounded caveats — BUY/SELL re-entry paths exercised; long validation timeout documented |
| Owner Strategy Tester | PENDING_OWNER |

## Local and review evidence

- `git diff --check`: PASS.
- JSON/YAML parse: PASS.
- C++ warning debt is unchanged and is not a MetaEditor result:
  `offline_suite.cpp` has unused `trim_s`/`MathAbs`; the T17.7 journal model
  has existing misleading-indentation warnings. No model failed.
- Final deep review v2 scanned 111 files and 1,206 grounded function packets:
  critical=4, error=55, warn=353, info=29. The prior T17.18 baseline was
  critical=4, error=55, warn=334, info=29; all four newly introduced v1
  errors were removed before this report. Remaining new warnings are
  complexity/metadata or reviewed detector false positives, not a new
  ownership/order bypass.
- Deep-review SHA-256: JSON
  `d92606e37bc6ea25c1802ad6365991b7fe22bb2ab47f3b60b52e67ac18d23ec8`;
  Markdown
  `6bc87133e20841ef8d12eec9ac0455dd2b910aa1db8f1eb53a9eeaf4e6e2ac6e`.

## TunnelVibemq5 evidence

- Dedicated workspace: `BD`; fixed terminal: MT5-2 build 6140; live trading
  was disabled by terminal preflight.
- Canonical EA SHA-256
  `ad344c9c461a43e4f90ab68ba6947fd9604d35b5a2cc3775b2bbbac41d4c141a`.
  All 83 canonical project files uploaded to the workspace matched their
  local bytes.
- The connector deploys only the selected EA into the terminal `Experts`
  tree, so compiling the canonical path could not resolve the project
  `Include` tree. A tunnel-only dependency-closure stage was therefore made
  from those 83 attested inputs; staged SHA-256
  `ece171010bc28c457966e821520b08e7fbc4b0aa35c8b1ee34bcfc6d5a40e3a3`.
  This stage compiled with 0 errors/0 warnings. It is not a repository file
  and does not replace the exact-head CI compile.
- Smoke `BT-20260904-020421-32DA64`: PASS; compile 0/0, tester completed,
  report parsed, no fatal/diagnostic/anomaly events.
- Default validation `BT-20260904-070949-5942DB`: infrastructure/liveness
  PASS with compile 0/0 and no parser anomaly, but economic/risk behavior is
  not acceptable as release evidence because it reached margin exhaustion and
  forced liquidation. The run used default Recovery OFF and therefore did not
  cover T17.19. Its log also exposed existing repeated closed-market retry and
  `NO_MONEY`/latch heartbeat noise. Exact account/trade figures remain in the
  private local evidence only.
- A first targeted set run proved a `.set` string-format staging error and was
  rejected before testing; this was test-harness input formatting, not an EA
  compile/runtime failure.
- Corrected Core-Pyramid-ON targeted smoke
  `BT-20260904-073840-4BA481`: PASS, compile 0/0, report parsed, no
  fatal/diagnostic/anomaly. It exercised
  active Recovery and Core Pyramid together but did not reach a terminal
  positive close, so it is not counted as T17.19 transition proof. The same
  set over the six-month validation window
  `BT-20260904-071744-B4BCF1` hit the bounded 1,200-second timeout without a
  fresh report; no product error is inferred from that timeout.
- Focused trigger set SHA-256
  `6a0957610879e7e2a6902482962bdf976dd55933edfbd00cfc653b1c19df6234`,
  job `BT-20260904-075004-E4F818`: PASS, compile 0/0, report parsed, no
  fatal/diagnostic/anomaly. The journal proves a real BUY-side path: exact
  positive protective close to
  `WAIT_RESET`; reset buffer to `ARMED`; return through the anchor to durable
  re-entry G1 `cycle=1/1`; a later exact positive protective close
  to `EXHAUSTED`. The DCA-block telemetry is present throughout the wait path.
  This proves one bounded runtime scenario, not restart, SELL-side, broker
  portability or owner acceptance.
- Core-Pyramid-ON trigger set SHA-256
  `0442589ee2e00a67ab9f90a2792f46da286ef32a96cae1bab11bf0deba774f49`,
  job `BT-20260904-075232-27C4F5`: PASS, compile 0/0, report parsed, no
  fatal/diagnostic/anomaly. It proves both directions with Core Pyramid
  composed ON: BUY and SELL each move from an exact positive protective close
  to `WAIT_RESET`, `ARMED`, durable G1 and then `EXHAUSTED` after the next
  exact positive protective close. DCA-block telemetry is present. The wait windows did
  not themselves satisfy an ADD trigger, so this runtime run proves that Core
  Pyramid remained composed, not that an ADD was executed inside WAIT/ARMED;
  the exact admission rule is covered by the 33/33 model/native contract and
  remains an explicit owner QA case.

Compile/native-script results are not owner Strategy Tester acceptance.
Tunnel test completion does not override the owner checklist. Release,
forward, live and merge remain false.
