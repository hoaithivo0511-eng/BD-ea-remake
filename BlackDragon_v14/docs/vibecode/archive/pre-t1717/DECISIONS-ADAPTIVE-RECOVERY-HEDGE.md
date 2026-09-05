# DECISIONS — Adaptive Recovery Hedge Integration

Status: OWNER-APPROVED DESIGN DIRECTION  
Method: VibeCodeKit-MQL5 Full / DECIDE  
Base: `main@e3aec40547ff0328b339bbd30155dc63bff38ba9`

## D-01 — Recovery starts only after configurable DCA depth

Decision: add a configurable activation threshold measured in DCA count for one Core direction.

- Initial Core order is excluded from the DCA count.
- Threshold crossing arms recovery; it does not itself bypass hedge-gap/risk gates.
- Arming is latched for the cycle after the threshold is first reached.

Reason: preserve the existing BlackDragon grid phase before recovery takes over.

## D-02 — Recovery hedge TP is EA-managed

Decision: no broker-side TP for recovery profit-taking.

- Hedge partial TP is triggered virtually by EA logic.
- Realized ledger updates only after confirmed closing deals.
- Broker-side SL is permitted after a remaining hedge has been locked net-positive.

Reason: a broker TP on a single hedge position conflicts with the required partial-close flow.

## D-03 — One logical hedge, smart-split physically when required

Decision: each hedge generation is one logical HedgeBundle equal to required hedge exposure.

- Default hedge ratio for v1 is fixed 1:1 against required exposure.
- If broker max-per-order is lower than required size, split into deterministic child requests.
- Generation count tracks logical recovery events, not physical ticket count.
- Never round total requested hedge exposure upward.

## D-04 — Core and Recovery ownership are separated

Decision: Recovery uses a separate RecoveryMagic/domain.

- Core positions remain owned by existing BlackDragon `Magic` and `CBasketManager`.
- Recovery positions are excluded from legacy BUY/SELL baskets and legacy side classification.
- Closing requests preserve the selected position's owner magic.

Reason: prevents Recovery hedge from triggering legacy MoneyGuard/TP/SL/Overlap/DCA logic as if it were a normal opposite Core basket.

## D-05 — Two recovery cycles may run in parallel

Decision: BUY-Core and SELL-Core cycles may recover simultaneously.

- Separate FSM, ledger, generation, anchors and command state per cycle.
- No cross-use of realized credit.
- Account-level emergency/margin gates remain shared.

## D-06 — Core partial-close policy is configurable

Decision: expose four modes:

1. `Oldest`
2. `Newest`
3. `Lossiest` by loss-per-lot
4. `ProRata`

No mode may consume more realized recovery credit than available after actual deal accounting.

Strategic note: `Oldest` generally best supports moving a BUY Core breakeven downward / SELL Core breakeven upward and therefore supports corridor creation, but this is not hardcoded as the only behavior.

## D-07 — Continue DCA after active hedge is optional

Decision: add `ContinueDcaAfterHedge_`.

- OFF is the safety default.
- ON keeps the existing BlackDragon DCA engine unchanged.
- Recovery does not create an alternate DCA engine.
- No DCA is allowed while the recovery cycle has an unresolved mutation chain.

Reason: preserve ability to reduce Core breakeven further while retaining the higher/lower hedge entry, but prevent races between DCA and recovery close/build commands.

## D-08 — Profit corridor is a first-class metric

Decision: measure the distance between net Core breakeven and opposite Recovery hedge net breakeven.

- Positive corridor means a simultaneous-profit price interval exists.
- This is an observability and optional optimization metric, not proof of guaranteed profit.
- `TargetRecoveryCorridorPips_ = 0` means no automatic target stop until evidence supports a configured value.

## D-09 — Do not auto top-up hedge after every DCA

Decision: continuing DCA does not immediately open a matching hedge after every new Core order.

Reason: immediate top-up at the new lower/higher price can drag the weighted hedge entry toward the Core and destroy the intended corridor advantage.

Protection against uncontrolled dilution is handled by explicit risk/coverage gates, not by unconditional per-DCA top-up.

## D-10 — Re-hedge uses exposure deficit

Decision:

```text
new hedge required = max(current Core exposure - active Recovery hedge exposure, 0)
```

A later re-hedge generation therefore fills the coverage deficit rather than stacking another full 100% hedge on top of surviving hedge volume.

## D-11 — Optional coverage/corridor thresholds have neutral defaults

Decision:

- `MinHedgeCoveragePercent_ = 0` => disabled until calibrated.
- `TargetRecoveryCorridorPips_ = 0` => disabled until calibrated.

Reason: do not invent backtest-sensitive thresholds during implementation.

## D-12 — Existing Gold pip convention remains source of truth

Decision: do not introduce `InpGoldConvention`/`InpGoldPipsPerUSD` as a parallel system.

Recovery must use/refactor the existing BlackDragon Gold convention so XAU 2/3-digit behavior stays consistent across Core and Recovery.

## D-13 — Legacy mode parity is mandatory

Decision: `RecoveryMode=OFF` must preserve BlackDragon v14.9 trading behavior.

Any implementation that changes Core basket membership, DCA indexing, legacy MoneyGuard scope, existing exit ordering or .set semantics while Recovery is OFF is a regression unless separately approved.

## D-14 — Shadow mode is part of the integration design

Decision: Recovery mode should support at least:

```text
OFF     - no Recovery decisions/actions
SHADOW  - calculate/log Recovery decisions, send no Recovery trade requests
ACTIVE  - execute Recovery FSM
```

Reason: obtain forward evidence on trigger, sizing, margin, corridor and conflicts before enabling live Recovery mutation.

## D-15 — Generation boundary is explicit

Decision: valid generations are `1..MaxHedgeGenerations_`.

- Starting generation `Max+1` is prohibited.
- Reaching generation `Max` does not automatically imply an immediate Global Stop merely because equality was reached.
- Stop policy may react to inability to start another generation or separate risk limits, but the counting boundary must not be off-by-one.
