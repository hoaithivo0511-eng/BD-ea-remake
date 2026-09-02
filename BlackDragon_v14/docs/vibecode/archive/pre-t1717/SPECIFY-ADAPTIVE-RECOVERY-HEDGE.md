# SPECIFY — Adaptive Recovery Hedge Integration for BlackDragon

Status: DESIGN CONTRACT CANDIDATE  
Method: VibeCodeKit-MQL5 Full  
Base: `main@e3aec40547ff0328b339bbd30155dc63bff38ba9`  
Scope: Recovery Hedge only. Legacy BlackDragon behavior must remain unchanged when Recovery is OFF.

## 1. Goal

Integrate an adaptive recovery hedge subsystem into BlackDragon without contaminating the existing Core BUY/SELL baskets.

Primary strategic objective:

1. A one-direction Core basket reaches a configurable DCA depth.
2. Recovery becomes armed.
3. After an additional adverse price gap, EA opens an opposite hedge equal to the required hedge exposure.
4. Hedge exit is managed by the EA using a virtual/soft TP; no broker TP is required for recovery profit taking.
5. At hedge profit target, EA closes only the configured hedge portion, books realized cash, uses that cash to partially close losing Core volume, and protects the remaining hedge.
6. Optionally, the original BlackDragon DCA chain may continue after the hedge is fully established, with the objective of moving Core breakeven through/under the opposite hedge breakeven and creating a positive recovery corridor.
7. BUY-Core and SELL-Core recovery cycles may coexist and progress independently.

## 2. Non-goals

- Do not merge Recovery positions into `BasketManager.buy/sell`.
- Do not reinterpret legacy `Flag_Use_hedge`; it remains Core two-sided-series behavior.
- Do not change legacy DCA lot/distance chain semantics.
- Do not change legacy Core behavior when RecoveryMode=OFF.
- Do not add a second Gold pip convention.
- Do not make Strategy Tester async claims; tester behavior remains evidence-bounded.

## 3. Recovery activation semantics

New input concept:

```cpp
input int RecoveryStartAfterDca_;
```

Definition:

- Core initial position is order #1 and is NOT counted as a DCA.
- `dcaCount = max(coreOpenPositions - 1, 0)` for activation.
- Recovery becomes ARMED once `dcaCount >= RecoveryStartAfterDca_`.
- Once armed for a cycle, the state is latched. Later partial closes/Overlap must not un-arm the cycle merely because the current open-position count decreases.
- The arming anchor is the actual confirmed `DEAL_PRICE` of the DCA that first satisfies the threshold.

Hedge trigger after arming:

- BUY Core: open SELL Recovery hedge when Bid <= anchor - HedgeGap.
- SELL Core: open BUY Recovery hedge when Ask >= anchor + HedgeGap.
- `HedgeGapPips_ = 0` means eligible to hedge immediately after the arming DCA is confirmed, subject to risk/execution gates.

## 4. Ownership model

Core and Recovery are separate domains:

```text
Core Magic      -> CBasketManager -> legacy Strategy/MoneyGuard/Exit
Recovery Magic  -> CRecoveryManager/CycleRegistry
```

Requirements:

- Recovery positions MUST NOT enter Core `BasketSide buy/sell`.
- Each Recovery position belongs to exactly one Core cycle and one hedge generation.
- BUY Core and SELL Core may each own an independent recovery cycle simultaneously.
- Realized Recovery cash is cycle-local; it must never be transferred between BUY-Core and SELL-Core cycles.

## 5. Logical hedge bundle and smart split

A hedge generation is one logical `HedgeBundle`, even if broker limits require multiple physical MT5 positions.

Example:

```text
required hedge = 12.37 lots
broker max per order = 5.00 lots
physical children = 5.00 + 5.00 + 2.37
logical generation = ONE generation, 12.37 lots total
```

Rules:

- Plan in integer volume units derived from `SYMBOL_VOLUME_STEP`.
- Respect `SYMBOL_VOLUME_MIN`, `SYMBOL_VOLUME_MAX`, `SYMBOL_VOLUME_STEP`, `SYMBOL_VOLUME_LIMIT`, margin checks, and symbol trading constraints.
- Never round hedge exposure upward.
- Child orders are submitted sequentially per cycle; each child must be confirmed before the next child is sent.
- Recovery state remains `HEDGE_BUILDING` until confirmed aggregate child volume reaches the planned target.
- Partial bundle fill is not equivalent to active/full hedge.
- If final residual volume is below tradable minimum, do not force a rounded-up child. Record the exact unhedged residual exposure.

## 6. Hedge profit-taking semantics

Recovery hedge TP is virtual/EA-managed.

- Do not attach a broker TP for recovery profit-taking.
- The trigger is evaluated against actual weighted hedge entry/breakeven and configured `HedgeTPPips_`.
- When soft TP is reached, close only `HedgePartialClosePercent_` of the logical active hedge bundle.
- Close allocation across physical hedge children should minimize request count while matching target volume without rounding up.
- Ledger updates occur only from confirmed closing deals.

A broker-side SL MAY be used after the remaining hedge has been locked into net-positive protection, subject to stops/freeze/tick constraints.

## 7. Core partial-close allocation modes

New enum concept:

```cpp
enum eRecoveryCoreCloseMode
{
   recovery_Oldest,
   recovery_Newest,
   recovery_Lossiest,
   recovery_ProRata
};
```

Semantics:

- `Oldest`: allocate recovery close volume to oldest Core tickets first.
- `Newest`: allocate to newest Core tickets first.
- `Lossiest`: rank by current loss-per-lot, most negative first; do not rank by absolute money loss because DCA lot sizes differ.
- `ProRata`: reduce Core tickets proportionally, with residual units distributed deterministically without exceeding recovery cash.

Planning may use current mark-to-market loss to choose candidate volumes; ledger debit must use actual realized closing deals.

## 8. Continue-DCA-after-hedge mode

New input concept:

```cpp
input bool ContinueDcaAfterHedge_;
```

OFF:
- Once Recovery hedge is active, Core DCA is locked until Recovery permits a later transition.

ON:
- Existing BlackDragon DCA chain remains the only Core DCA engine.
- Existing `MaxOrdersBuy/MaxOrdersSell`, lot chain, distance chain, `MinuteStop`, one-order-per-bar, pause/news and async busy rules remain authoritative.
- Recovery does not create a second DCA chain.
- DCA is never allowed while a Recovery mutation chain is unresolved.

DCA may be allowed only in stable states such as `HEDGE_ACTIVE`, `HEDGE_LOCKED`, and `REHEDGE_PENDING`. It is forbidden in `HEDGE_BUILDING`, hedge/core close pending, reconcile-required, hard-pause and global-stop states.

## 9. Recovery corridor objective

For BUY Core + SELL Recovery hedge:

```text
Corridor = HedgeSellNetBE - CoreBuyNetBE
```

For SELL Core + BUY Recovery hedge:

```text
Corridor = CoreSellNetBE - HedgeBuyNetBE
```

Interpretation:

- Corridor < 0: no simultaneous-profit price band yet.
- Corridor = 0: breakevens touch.
- Corridor > 0: a price interval exists in which both Core and remaining hedge can be net-positive after modeled costs.

Optional safety/optimization inputs may exist:

```cpp
input double MinHedgeCoveragePercent_;       // 0 = disabled
input double TargetRecoveryCorridorPips_;    // 0 = disabled
```

These values must not be invented by implementation. Default 0 means no extra strategy gate until backtest/forward evidence supports a threshold.

## 10. Re-hedge sizing

Re-hedge must not blindly hedge 100% of current Core while prior locked hedge remains open.

```text
DesiredHedgeUnits = CurrentCoreUnits
ExistingRecoveryHedgeUnits = sum(all active recovery hedge children for cycle)
NewHedgeRequiredUnits = max(DesiredHedgeUnits - ExistingRecoveryHedgeUnits, 0)
```

- Each re-hedge event creates one new logical generation.
- Smart split applies to each generation.
- Physical child count does not increment generation count.
- Allowed generations are `1..MaxHedgeGenerations_`; attempting to start generation `Max+1` is forbidden.

## 11. Parallel recovery cycles

Two cycles may coexist:

```text
BUY Core cycle  -> SELL Recovery hedge
SELL Core cycle -> BUY Recovery hedge
```

They have separate FSM state, ledger, anchors, generation count, child tickets and command identity.

Account-level controls remain shared:
- margin/emergency stop,
- account-wide MoneyGuard actions,
- rate limit on recovery commands.

## 12. Evidence boundary

This specification does not claim runtime correctness. Build/release requires later evidence gates:

- unit/static tests,
- native MetaEditor 0 errors / 0 warnings,
- actual Recovery scenario execution,
- Strategy Tester real-tick scenarios,
- restart/reconcile tests,
- async duplicate/fault-injection tests where available,
- forward demo before LIVE eligibility.
