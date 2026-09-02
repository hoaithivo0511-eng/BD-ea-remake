# Current Version — BlackDragon

## Canonical identity

| Layer | Canonical value | Source of truth |
|---|---|---|
| Product/binary version | `15.00` | `BlackDragon.mq5 #property version` |
| Panel display version | `15.00` | `Config.mqh BD_VERSION` |
| Runtime task lineage | `T17.17` | active spec/decision/verify documents |
| EA entry point | `Experts/BlackDragon/BlackDragon.mq5` | only production `.mq5` under `Experts/` |
| Active branch | `feat/t17-full-pyramid` | PR #28 head |
| PR state | Draft / open / not merged | GitHub |
| Owner Strategy Tester | `PENDING_OWNER` | release gate |

The directory name `BlackDragon_v14` is retained as an installation/path
compatibility boundary. It does not override the binary version.

## What is and is not an old version

- `Recovery*Base.mqh`, `StrategyT176Base.mqh`,
  `RecoveryArcsStackT177HedgeLadderC4Base.mqh` and similar files are live
  compatibility layers. The production include graph reaches them.
- `RunT17xx*.mq5` and matching C++ models are regression suites, not old EA
  binaries. They remain because later behavior depends on earlier contracts.
- Documents below `docs/vibecode/archive/` are frozen historical evidence.
  They are not current instructions.
- Git branches preserve development checkpoints. Branch removal is a
  separate remote-history operation and was not mixed into source cleanup.

## Canonical composition

The current entry point reaches 79/79 tracked runtime headers with no missing
project include. Runtime modules include signal, grid/DCA, Core Pyramid,
Recovery/ARCS/Hedge Pyramid, Overlap, MoneyGuard, execution journal,
persistence, panel and broker/unit policy.

CI treats the repository as coherent only when:

1. every runtime header is reachable from the entry point;
2. binary and Panel versions match;
3. exactly one workflow exists;
4. every native `Run*.mq5` and every C++ model is listed in that workflow;
5. known stale/generated paths remain absent.

These rules are executable in
`Scripts/BlackDragon/Tests/repository_contract.py`.

## Release status

T17.17 deterministic and exact-head Windows CI evidence exists for the
pre-cleanup tree. Cleanup exact-head CI is required again because the displayed
version and artifact provenance change. Strategy Tester remains pending even
after a green compile/native run. No forward/live eligibility is inferred.
