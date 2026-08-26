# T17.10 Owner Strategy Tester QA

Use only the EX5 whose SHA256 matches exact final HEAD/TREE provenance. Keep PR #28 Draft.

1. Run the current owner `.set` unchanged with `LEGACY_COMPAT`; compare entry, DCA, TP/SL/trailing and spread/deviation behavior to the T17.9 baseline.
2. Copy the `.set`, change only `UnitSystemMode_=PIP_UNIFIED`, then intentionally migrate TP_, SL_, iTS, iTD, MaxSpred and Slippage_ values from legacy reference points to desired pips.
3. Re-run DCA on the broker symbols actually used, including both quote-digit variants when available.
4. Confirm Recovery/Pyramid `*Pips*` behavior did not change between modes.
5. Confirm Basket breakeven includes swap/commission correctly on a symbol where tick size differs from point.
6. Preserve `.set`, tester/terminal logs, report, terminal build, symbol properties and exact EX5 hash.

No forward/live or release claim until owner Strategy Tester, restart/recovery and broker-parity evidence pass.
