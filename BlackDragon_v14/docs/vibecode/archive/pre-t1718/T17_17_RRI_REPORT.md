# T17.17 RRI Report

Risk tier: P0/P1 Full.

| Risk | Guard | Locked proof |
|---|---|---|
| Exact internal ARCS SL is misclassified during concurrent Overlap | A1/A2/A5 | Side-cycle counterexample; exact deal identity remains mandatory |
| Account-wide emergency loses ownership of a concurrent SL | A3/A4 | Expected-SL bypass remains disabled while account-wide close is pending |
| Unknown/manual broker close is swallowed as expected | A2/A4 | Wrong owner/reason/price/identity remains on fail-closed external path |
| Flat reset hides unresolved exposure or execution | A5/A6/A8 | Reset requires account guard completion, zero positions, quiet journal and idle Recovery coordinator |
| Persistence failure silently re-arms Strategy | A2/A6/A7 | Overlap reset is atomic; failure restores/re-latches fail-closed state and guard retries |
| C++/MQL/source composition diverges | A10/A12 | Matching model/native matrix, source contracts and exact-head MetaEditor compile |
| Tester completion is overstated | A11 | CI proves deterministic behavior only; owner rerun remains PENDING |

Residual owner-test risk: real broker callback ordering, restart with persisted Overlap state, slippage around simultaneous SL/MoneyTP, and the unproven EX5 used for the supplied log.

