//+------------------------------------------------------------------+
//| RecoveryDca.mqh — T7 Continue-DCA + corridor/coverage gate       |
//| Invariants: filter-only integration; legacy TryGridAdd remains   |
//|             the sole Core DCA order-generation mechanism.        |
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_DCA_MQH
#define BD_RECOVERY_DCA_MQH

#include "RecoveryEngine.mqh"
#include <BlackDragon/EntryFilters.mqh>
#include <BlackDragon/BasketManager.mqh>

bool Recovery_ValidateDcaConfig(const eRecoveryMode mode,
                                const double minCoveragePercent,
                                const double targetCorridorPips,
                                string &why)
{
   why = "";
   if(mode == recovery_OFF) return true; // exact legacy-init parity when Recovery is disabled
   if(minCoveragePercent < 0.0 || minCoveragePercent > 100.0)
   {
      why = "MinHedgeCoveragePercent_ must be in [0,100]";
      return false;
   }
   if(targetCorridorPips < 0.0)
   {
      why = "TargetRecoveryCorridorPips_ must be >= 0";
      return false;
   }
   return true;
}

bool Recovery_DcaPostHedgeStableState(const eRecoveryState state)
{
   return state == recovery_HEDGE_ACTIVE ||
          state == recovery_HEDGE_LOCKED ||
          state == recovery_REHEDGE_PENDING;
}

// OFF and SHADOW never alter legacy DCA. In ACTIVE, CORE_ONLY/ARMED remain
// eligible because Recovery has not yet established an active hedge. Once a
// hedge exists, only the explicitly stable states may continue DCA and only
// when the owner enabled ContinueDcaAfterHedge_. Mutation/pause/reconcile
// states are fail-closed.
bool Recovery_DcaStateAllows(const eRecoveryMode mode,
                             const bool continueAfterHedge,
                             const eRecoveryState state)
{
   if(mode != recovery_ACTIVE) return true;

   if(state == recovery_CORE_ONLY || state == recovery_ARMED)
      return true;

   if(Recovery_DcaPostHedgeStableState(state))
      return continueAfterHedge;

   return false;
}

bool Recovery_DcaCoverageAllows(const double minCoveragePercent,
                                const double currentCoreLots,
                                const double activeHedgeLots)
{
   if(minCoveragePercent <= 0.0) return true;
   if(currentCoreLots <= 0.0) return false;
   double coverage = Recovery_CoveragePercent(currentCoreLots, activeHedgeLots);
   return coverage + 1e-9 >= minCoveragePercent;
}

double Recovery_CorridorPipsPure(const eRecoveryCoreDirection dir,
                                 const double coreNetBE,
                                 const double hedgeNetBE,
                                 const double pipSize)
{
   if(pipSize <= 0.0) return 0.0;
   return Recovery_CorridorPrice(dir, coreNetBE, hedgeNetBE) / pipSize;
}

// Target means "stop adding Core DCA once the desired positive corridor has
// already been reached". Negative/zero corridor therefore does not block DCA.
bool Recovery_DcaCorridorAllows(const double targetCorridorPips,
                                const eRecoveryCoreDirection dir,
                                const double coreNetBE,
                                const double hedgeNetBE,
                                const double pipSize)
{
   if(targetCorridorPips <= 0.0) return true;
   if(pipSize <= 0.0 || coreNetBE <= 0.0 || hedgeNetBE <= 0.0) return false;
   double corridorPips = Recovery_CorridorPipsPure(dir, coreNetBE, hedgeNetBE, pipSize);
   return corridorPips + 1e-9 < targetCorridorPips;
}

bool Recovery_DcaGateAllows(const eRecoveryMode mode,
                            const bool continueAfterHedge,
                            const eRecoveryState state,
                            const double minCoveragePercent,
                            const double targetCorridorPips,
                            const eRecoveryCoreDirection dir,
                            const double currentCoreLots,
                            const double coreNetBE,
                            const double activeHedgeLots,
                            const double hedgeNetBE,
                            const double pipSize)
{
   if(!Recovery_DcaStateAllows(mode, continueAfterHedge, state)) return false;
   if(mode != recovery_ACTIVE) return true;

   // Pre-hedge states retain legacy DCA even when ContinueDcaAfterHedge_=false.
   if(!Recovery_DcaPostHedgeStableState(state)) return true;

   if(!Recovery_DcaCoverageAllows(minCoveragePercent, currentCoreLots, activeHedgeLots))
      return false;
   if(!Recovery_DcaCorridorAllows(targetCorridorPips, dir, coreNetBE, hedgeNetBE, pipSize))
      return false;
   return true;
}

// Read current broker-observable Recovery hedge exposure for T7 gates.
// Registry metrics remain useful for telemetry, but DCA permission must not
// depend on a cached value that may lag the HEDGE_BUILDING -> HEDGE_ACTIVE
// transition. Entry costs are read only when the corridor gate is enabled.
double Recovery_DcaPositionEntryCosts(const ulong positionIdentifier,
                                      const string symbol,
                                      const long recoveryMagic)
{
   if(positionIdentifier == 0 || !HistorySelectByPosition(positionIdentifier)) return 0.0;
   double costs = 0.0;
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0) continue;
      if(HistoryDealGetString(deal, DEAL_SYMBOL) != symbol ||
         HistoryDealGetInteger(deal, DEAL_MAGIC) != recoveryMagic)
         continue;
      long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_IN && entry != DEAL_ENTRY_INOUT) continue;
      costs += HistoryDealGetDouble(deal, DEAL_COMMISSION)
             + HistoryDealGetDouble(deal, DEAL_FEE);
   }
   return costs;
}

bool Recovery_ReadDcaHedgeMetrics(const string symbol,
                                  const long recoveryMagic,
                                  const eRecoveryCoreDirection dir,
                                  const bool needNetBE,
                                  double &activeLots,
                                  double &netBE)
{
   activeLots = 0.0;
   netBE = 0.0;
   long wantedType = Recovery_HedgeDirection(dir) == 0 ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   double weighted = 0.0;
   double signedCosts = 0.0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != symbol ||
         PositionGetInteger(POSITION_MAGIC) != recoveryMagic ||
         PositionGetInteger(POSITION_TYPE) != wantedType)
         continue;

      double lots = PositionGetDouble(POSITION_VOLUME);
      if(lots <= 0.0) continue;
      activeLots += lots;
      if(!needNetBE) continue;

      weighted += PositionGetDouble(POSITION_PRICE_OPEN) * lots;
      signedCosts += PositionGetDouble(POSITION_SWAP);
      ulong identifier = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
      signedCosts += Recovery_DcaPositionEntryCosts(identifier, symbol, recoveryMagic);
   }

   if(activeLots <= 0.0) return false;
   if(!needNetBE) return true;

   double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickSize <= 0.0 || tickValue <= 0.0) return false;
   bool hedgeIsBuy = wantedType == POSITION_TYPE_BUY;
   netBE = Recovery_NetBreakevenFromCosts(weighted / activeLots,
                                           activeLots,
                                           signedCosts,
                                           tickValue,
                                           tickSize,
                                           hedgeIsBuy);
   return netBE > 0.0;
}

// RETRO-A2: a Strategy Tester pass that reaches an entry/DCA gate while
// Recovery ACTIVE is still not ready has no valid behavioral evidence to
// collect. Stop that pass instead of emitting the same warning for months of
// modelled time. Live/forward runtime remains fail-closed and keeps running so
// higher-scope risk/exit handling is still available.
void Recovery_StopTesterOnStartupBlock(const string scope)
{
   if(!MQLInfoInteger(MQL_TESTER)) return;
   Log_Error("Recovery", "Strategy Tester stopped: Recovery ACTIVE startup is not reconciled/ready (" + scope + ")");
   TesterStop();
}

// ACTIVE startup gate for automated NEW SERIES. OFF/SHADOW are exact no-ops.
// T11: a fail-closed readiness block must be visible in Journal rather than
// silently consuming an otherwise valid signal.
class CRecoveryStartupFilter : public IEntryFilter
{
private:
   CRecoveryEngine *m_recovery;
public:
   CRecoveryStartupFilter(CRecoveryEngine *recovery) { m_recovery = recovery; }
   bool Allow(const EAContext &ctx, const int dir)
   {
      if(RecoveryMode_ != recovery_ACTIVE) return true;
      if(m_recovery == NULL)
      {
         Log_Warn("Recovery", "newseriesgate" + (string)dir,
                  "new Core series blocked: Recovery engine is unavailable");
         Recovery_StopTesterOnStartupBlock("new-series engine unavailable");
         return false;
      }
      if(!m_recovery.ActiveReady())
      {
         Log_Warn("Recovery", "newseriesgate" + (string)dir,
                  "new Core series blocked: Recovery ACTIVE is not reconciled/ready");
         Recovery_StopTesterOnStartupBlock("new-series gate");
         return false;
      }
      return true;
   }
};

// Adapter into the existing Strategy grid-filter chain. It never opens a
// hedge or a Core order and never mutates Recovery state. Recovery children
// remain outside CBasketManager because they use RecoveryMagic_.
class CRecoveryDcaFilter : public IEntryFilter
{
private:
   CRecoveryEngine *m_recovery;
   CBasketManager  *m_basket;

public:
   CRecoveryDcaFilter(CRecoveryEngine *recovery, CBasketManager *basket)
   {
      m_recovery = recovery;
      m_basket   = basket;
   }

   bool Allow(const EAContext &ctx, const int dir)
   {
      // Mandatory parity: SHADOW observes only and OFF is a no-op.
      if(RecoveryMode_ != recovery_ACTIVE) return true;
      if(m_recovery == NULL || m_basket == NULL)
      {
         Log_Warn("Recovery", "dcagate" + (string)dir,
                  "Core DCA blocked: Recovery engine/basket adapter unavailable");
         Recovery_StopTesterOnStartupBlock("DCA adapter unavailable");
         return false;
      }
      if(!m_recovery.ActiveReady())
      {
         Log_Warn("Recovery", "dcagate" + (string)dir,
                  "Core DCA blocked: Recovery ACTIVE is not reconciled/ready");
         Recovery_StopTesterOnStartupBlock("DCA gate");
         return false;
      }

      eRecoveryCoreDirection recoveryDir =
         dir == BD_DIR_BUY ? recovery_CORE_BUY : recovery_CORE_SELL;
      SRecoveryCycle cycle;
      m_recovery.GetCycle(recoveryDir, cycle);

      // State/owner switch can decide most calls without broker scans.
      if(!Recovery_DcaStateAllows(RecoveryMode_, ContinueDcaAfterHedge_, cycle.state))
      {
         Log_Warn("Recovery", "dcastate" + (string)dir,
                  "Core DCA blocked by Recovery state=" + Recovery_StateName(cycle.state) +
                  "; ContinueDcaAfterHedge=" + (ContinueDcaAfterHedge_ ? "true" : "false"));
         return false;
      }
      if(!Recovery_DcaPostHedgeStableState(cycle.state))
         return true;

      double coreLots = dir == BD_DIR_BUY ? m_basket.buy.totalLots : m_basket.sell.totalLots;
      double coreBE   = dir == BD_DIR_BUY ? m_basket.buy.breakeven : m_basket.sell.breakeven;
      double pipSize  = Recovery_PipSizePure(Sym_IsGold(), ctx.point, ctx.digits);

      double hedgeLots = cycle.activeHedgeLots;
      double hedgeBE   = cycle.hedgeNetBE;
      bool needCoverage = MinHedgeCoveragePercent_ > 0.0;
      bool needCorridor = TargetRecoveryCorridorPips_ > 0.0;
      if(needCoverage || needCorridor)
      {
         if(!Recovery_ReadDcaHedgeMetrics(_Symbol, RecoveryMagic_, recoveryDir,
                                          needCorridor, hedgeLots, hedgeBE))
         {
            Log_Warn("Recovery", "dcametric" + (string)dir,
                     "Core DCA blocked: required live Recovery hedge metrics are unavailable");
            return false;
         }
      }

      return Recovery_DcaGateAllows(RecoveryMode_,
                                    ContinueDcaAfterHedge_,
                                    cycle.state,
                                    MinHedgeCoveragePercent_,
                                    TargetRecoveryCorridorPips_,
                                    recoveryDir,
                                    coreLots,
                                    coreBE,
                                    hedgeLots,
                                    hedgeBE,
                                    pipSize);
   }
};

#endif // BD_RECOVERY_DCA_MQH