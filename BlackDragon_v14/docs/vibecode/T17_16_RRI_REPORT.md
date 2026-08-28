# T17.16 RRI Report

Risk tier: P0/P1 Full.

| Risk | Guard | Locked proof |
|---|---|---|
| Rebase bypasses Hedge safety gates | A1/A5 | Exact stage+target admission tests; target-change stale marker test |
| Broker split becomes over-throttled | A3/A4 | True partial child completes without a second stage gate |
| Restart loses admission or capacity state | A6/A8 | Persist-before-open marker and exposure-bound terminal global state |
| NO_MONEY only blocks one module/bar | A2/A8 | Shared legacy/owned OPEN contract and new-bar negative test |
| Margin threshold/unit drift | A9 | Required margin in account currency with independent 110% oracle |
| MQL/C++ behavior mismatch | A10 | Matching model and native tests plus MetaEditor compile |
| Multi-file composition drift | A12 | Exact source-contract paths and full exact-head CI |

Residual risk requiring owner tester: broker margin model changes, terminal restart timing, spread/slippage, stopout topology and full-period trade distribution.
