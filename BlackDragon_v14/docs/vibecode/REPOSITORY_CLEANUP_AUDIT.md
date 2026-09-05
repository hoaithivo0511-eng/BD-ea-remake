# Repository Cleanup Audit

Date: 2026-09-02

Methodology: Vibecode MQL5 Full

Scope: repository hygiene and version-source alignment; no trading-semantic change

## Baseline locked before mutation

- Remote PR #28 HEAD: `b87bd3cf3d3a1c23d748ed0b4addb95a8ea376b4`
- Remote/local tree: `2c1940de27fd6547eee17eb6c34683292c0d189e`
- PR: Draft, open, not merged
- Tracked files: 307
- Workflows: 27
- Runtime headers: 80
- Vibecode root documents: 117
- Remote branches observed: 34, all reported unprotected; rulesets: none

## Audit method

1. Traverse literal project includes recursively from `BlackDragon.mq5`.
2. Compare every tracked `.mqh` with the production-reachable set.
3. Compare every native/model/source contract against the latest exact-head
   workflow.
4. Search repository-wide incoming references for generated, bundled and
   legacy files.
5. Compare all visible version sources and test/provenance documents.
6. Read GitHub PR/branch/ruleset state before any remote update.

Unified deep review Stage 0–7 scanned 107 MQL source files:
`critical=4`, `error=56`, `warn=338`, `info=29`, readiness
`release-blocked`. Counts match the established T17.17 review; findings are
pre-existing risk/complexity/release debt and none invalidates the bounded
repository-hygiene change.

- `deep-review.json` SHA256:
  `7ddbfc74d06082d21e5f029d2bfd72f970e2fdd18d551a1f39d6ab09b18a8c64`
- `deep-review.md` SHA256:
  `beb2c67bbcb53163d854d727742763f680b2dc8d0f2a7e1ee107dfa36f690325`

## Findings and disposition

| Class | Finding | Disposition |
|---|---|---|
| Canonical runtime | `BlackDragon.mq5` is the only production entry and already identifies binary v15.00/T17.17 | Keep |
| Version conflict | Panel showed 14.9.0 while binary property was 15.00 | Align Panel constant to 15.00; no trading/persistence use |
| Live compatibility layers | 79 headers are reachable through wrapper/base composition | Keep all |
| Dead source | `CorePyramidT177Anchor.mqh` had zero incoming references and was not reachable | Delete |
| Native test gaps | `RunPyramidT17Tests` and `RunRecoveryFoundationTests` existed but were omitted from latest native matrix | Add; native matrix becomes 27/27 files |
| Model junk | `bench.cpp` reimplemented old 14.7.1 approximations and was not a contract/model gate | Delete |
| CI duplication | 26 historical workflows were superseded by the T17.17 full matrix; several still triggered on the active branch | Delete; retain one canonical workflow |
| CI self-mutation | Legacy compile workflow wrote `ci-result/RESULT.md` back to branches | Delete workflow and generated result |
| Bundled tool | `vibecode-kit-v5.1.skill` was a stale binary tool copy, not EA source | Delete |
| Stale owner guide | HTML guide claimed v14.7.1 and omitted current Recovery/Pyramid behavior | Delete; current code/docs remain authoritative |
| Governance history | 108 pre-current documents/evidence files cluttered the active docs root | Move to frozen archive; do not erase decisions |
| Root docs | README/HANDOFF described 14.7.x, PR #2 and pending compile claims | Replace with current canonical handoff |

## Deliberately retained

- All 79 runtime-reachable headers, including versioned base/wrapper names.
- All 27 native MQL suites and all 37 C++ deterministic model suites.
- Source contracts T17.11–T17.17.
- T17.17 spec, decisions, contract, plan, scan, RRI, verify, retro and owner QA.
- Historical governance in `docs/vibecode/archive/`.
- `feat/recovery-t16-arcs-stacked` because it is PR #28 base.
- Remote branches: no branch ref was deleted in this source-tree cleanup.

## Resulting tree inventory

| Metric | Before | After |
|---|---:|---:|
| Tracked files | 307 | 280 |
| Tracked blob bytes | 2,277,598 | 1,827,567 |
| GitHub workflows | 27 | 1 |
| Runtime headers | 80 (1 orphan) | 79 (79 reachable) |
| Native MQL suites in CI | 25 of 27 | 27 of 27 |
| C++ model files | 38 (including stale benchmark) | 37 contract suites |
| Current vibecode root docs | 117 | 12 |
| Frozen archived evidence files | 0 | 109 |

Tracked content is reduced by 450,031 bytes (19.8%) while historical
governance remains available under the archive and in Git history.

## Remote branch follow-up

The repository exposes 34 branches. `main`,
`feat/recovery-t16-arcs-stacked` and `feat/t17-full-pyramid` are definitely
retained. The other 31 are branch-cleanup candidates, but deleting them could
remove the only named ref to historical commits. They require a separate
reachability/PR audit and explicit owner branch manifest; they are not needed
to make the PR tree reviewable.

## Contract

- No input/default, entry, lot, DCA, Pyramid, Recovery, Hedge, target, stop,
  MoneyGuard or execution ownership rule may change.
- No persistence filename/layout/policy revision may change.
- No merge, Ready-for-Review or live trading action.
- Exact remote HEAD must still match the locked parent immediately before
  create-tree/create-commit/update-ref.
- Cleanup is accepted only after local contracts/models, exact-head Windows
  MetaEditor, all 27 native suites and artifact provenance pass.
- Strategy Tester remains `PENDING_OWNER`.

## Current follow-on

T17.18 removed the legacy dashboard/button composition and retained
`ShowWmfSignals`. T17.19 adds terminal positive-SL Recovery re-entry without
changing that cleanup result. The inventory above remains the exact cleanup
baseline; current runtime authority is `T17_19_*` plus `PROJECT_STATE.yaml`.
