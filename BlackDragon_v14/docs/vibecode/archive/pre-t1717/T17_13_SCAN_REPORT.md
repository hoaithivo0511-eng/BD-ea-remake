# T17.13 SCAN REPORT — Non-exclusive Core growth

## Provenance

- Repository: `hoaithivo0511-eng/BD-ea-remake`
- PR: `#28` (`OPEN`, `DRAFT`, `UNMERGED`)
- Branch: `feat/t17-full-pyramid`
- Build baseline HEAD: `47ae97f4ebae00beb46c2fa0f8efb49ac142b7c5`
- Build baseline TREE: `35144eaf9de8d20826b193d212c166cc24fdd46e`
- Owner source: chat plan continuation on 2026-08-27

## Confirmed chain

The 11-BUY observation has `lastOpen=4091.635`, `ask=4049.197`, spacing `13.0` pips and pip-price `0.10`. The spacing predicate is true, but pre-leg/read-only Recovery and Overlap ownership could prevent Core growth from reaching the execution seam.

## Affected composition

- Recovery Core-DCA and Core-Pyramid admission wrappers.
- Overlap pre-leg ownership and same-side block projection.
- Strategy composition adapter and exact-root includes.
- Deterministic/source/native verification and exact-HEAD QA packaging.

## Preserved boundaries

- No input, entry signal, lot/risk, exit, unit or persisted-enum change.
- Broker mutation and reconciliation remain exclusive/fail-closed.
- Compile evidence is not Strategy Tester, forward or live evidence.
