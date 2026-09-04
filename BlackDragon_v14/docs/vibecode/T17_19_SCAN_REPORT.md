# T17.19 Scan Report

Input log: `20260904.log`, SHA-256
`85af0f469ccde3be1dfe0681bf18277e9e2e78c1013e60e546966bf7e55e31ea`.

The UTF-16LE file contains three concatenated Strategy Tester sessions. One
session reaches terminal Recovery with Hedge `0` while Core exposure remains,
then Core DCA continues until a new order is rejected for insufficient margin
and the account reaches forced liquidation. Exact account/trade figures remain
local-only and are intentionally not published in repository documentation.

The source trace confirms this is the current T17.11 policy, not state
corruption: `StartGeneration` refuses generations at the configured maximum,
`TerminalNoHedge` makes live Hedge metrics inapplicable, and
`ContinueDcaAfterHedge_` admits Core DCA. The existing
`RecoveryReentryBufferPips_` only governs the optional Global-SL transition,
which was disabled in the supplied run.

The log has no clear RECONCILE/timeout corruption signature. Repeated SL rows
are child deals, so T17.19 must evaluate complete-chain cash and exact ownership
rather than treating one child result as the chain result.

The requested mechanism reduces the uncovered terminal window; it does not
guarantee against forced liquidation when order/lot/risk caps and account loss
stops are disabled.
