# T10 Runtime QA

Status: FIX IMPLEMENTED; RE-VERIFY REQUIRED.

Owner Strategy Tester evidence exposed two integration bugs:
1. Expected Recovery protective SL (`DEAL_REASON_SL`) was classified as external and latched reconciliation.
2. MoneyGuard ran below Recovery blocking-work, so a reconcile hold could freeze money TP/SL.

T10 fixes the SL classifier with owner/state/lock-price evidence, moves MoneyGuard before Recovery blocking-work while keeping unresolved broker-close protection first, and localizes Recovery input groups 16–17. Input identifiers and enum numeric values are unchanged.

Scope reminder: account money TP/SL uses whole-account floating P/L; Magic/Buy/Sell/hedged money guards remain Core-basket scope and intentionally exclude RecoveryMagic.

Runtime ACTIVE remains unproven until exact compile/regression and owner Strategy Tester rerun pass.