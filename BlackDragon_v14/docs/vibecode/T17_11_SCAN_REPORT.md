# T17.11 SCAN REPORT — Recovery runtime liveness and admission

## Provenance

- Repository: `hoaithivo0511-eng/BD-ea-remake`
- PR: `#28` (`OPEN`, `DRAFT`, `UNMERGED`)
- Branch: `feat/t17-full-pyramid`
- Baseline HEAD: `e0ad9c59bac25e3e194d7bd917a80864cf4eecd9`
- Baseline TREE: `87dff344c2879c9a2019677e10b26e81966614c8`
- Owner contract: PR comment `5419070453`

The remote HEAD matches the approved baseline. No contract rebase is required.

## Confirmed failure chains

| ID | Severity | Baseline path | Failure |
| --- | --- | --- | --- |
| R11-01 | P0 | T17.8 wrapper `Drive()` | A stable BUY TP wait returns before SELL is driven. |
| R11-02 | P0 | ARCS `LOCKED` projection + DCA filter | Exhausted generation with Core>0/Hedge=0 is projected as a live-Hedge state and the metric reader blocks DCA. |
| R11-03 | P1 | top-level `OnInit()` | T5/T6 validators exist but are not composed into the active init gate. |
| R11-04 | P1 | legacy Core `OpenMarket()` + `TryGridAdd()` | `NO_MONEY` is not retried inside one send, but the same due DCA is re-submitted every tick. |

## Preserved boundaries

- No user-facing input or persisted-enum change.
- No T17.10 unit conversion change.
- Preserve T17.8 read-only steady wait and T17.9 REAL-TP settlement.
- Preserve strict Recovery execution identity and one-mutation serialization.
- No Strategy Tester or live-ready claim from deterministic evidence.

