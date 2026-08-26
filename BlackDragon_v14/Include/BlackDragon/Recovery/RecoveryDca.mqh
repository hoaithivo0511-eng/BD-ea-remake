//+------------------------------------------------------------------+
//| RecoveryDca.mqh — T17.6 Continue-DCA + corridor/coverage gate    |
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
   if(minCoveragePercent < 0.0)
   {
      why = "MinHedgeCoveragePercent_ must be >= 0";
      return false;
   }
   if(targetCorridorPips < 0.0)
   {
      why = "TargetRecoveryCorridorPips_ must be >= 0";
      return false;
   }
   return true;
}

// T17.11: one authoritative top-level composition. Each existing validator
// retains its own Recovery-OFF bypass; the T17 cross-input validator remains
// unconditional because a staged Pyramid configured while Recovery is OFF is
// an existing fail-fast contract, not a Recovery-only value.
bool Recovery_ValidateCompleteConfig(const long coreMagic,
                                     const long marginMode,
                                     string &why)
{
   string detail = "";
   why = "";
   if(!Recovery_ValidateFoundation(RecoveryMode_, coreMagic, RecoveryMagic_,
                                   RecoveryStartAfterDca_, marginMode, detail))
   { why = "Foundation: " + detail; return false; }
   if(!Recovery_ValidateShadowConfig(RecoveryMode_, HedgeGapPips_, detail))
   { why = "Shadow: " + detail; return false; }
   if(!Recovery_ValidateT5Config(RecoveryMode_, HedgeTPPips_,
                                 HedgePartialClosePercent_, CoreCloseMode_, detail))
   { why = "T5: " + detail; return false; }
   if(!Recovery_ValidateT6Config(RecoveryMode_, HedgeLockNetProfitPips_,
                                 HedgeLockSafetyBufferPips_, ReHedgeGapPips_,
                                 MaxHedgeGenerations_, detail))
   { why = "T6: " + detail; return false; }
   if(!Recovery_ValidateDcaConfig(RecoveryMode_, MinHedgeCoveragePercent_,
                                  TargetRecoveryCorridorPips_, detail))
   { why = "DCA: " + detail; return false; }
   if(!Recovery_T16ValidateConfig(detail))
   { why = "T16/T17: " + detail; return false; }
   if(!Recovery_T17ValidateCrossInputs(detail))
   { why = "Recovery/Pyramid cross-input: " + detail; return false; }
   return true;
}

bool Recovery_DcaPostHedgeStableState(const eRecoveryState state)
{
   return state == recovery_HEDGE_ACTIVE ||
          state == recovery_HEDGE_LOCKED ||
          state == recovery_REHEDGE_PENDING;
}

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

bool Recovery_T1711TerminalNoHedgeDcaAllowsPure(const eRecoveryMode mode,
                                                const bool continueAfterHedge,
                                                const bool terminalNoHedge)
{
   return mode == recovery_ACTIVE && continueAfterHedge && terminalNoHedge;
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
   if(!Recovery_DcaPostHedgeStableState(state)) return true;
   if(!Recovery_DcaCoverageAllows(minCoveragePercent, currentCoreLots, activeHedgeLots))
      return false;
   if(!Recovery_DcaCorridorAllows(targetCorridorPips, dir, coreNetBE, hedgeNetBE, pipSize))
      return false;
   return true;
}

double Recovery_DcaPositionEntryCosts(const ulong positionIdentifier,
                                      const string symbol,
                                      const long ownerMagic)
{
   if(positionIdentifier == 0 || !HistorySelectByPosition(positionIdentifier)) return 0.0;
   double costs = 0.0;
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0) continue;
      if(HistoryDealGetString(deal, DEAL_SYMBOL) != symbol ||
         HistoryDealGetInteger(deal, DEAL_MAGIC) != ownerMagic)
         continue;
      long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_IN && entry != DEAL_ENTRY_INOUT) continue;
      costs += HistoryDealGetDouble(deal, DEAL_COMMISSION)
             + HistoryDealGetDouble(deal, DEAL_FEE);
   }
   return costs;
}

// T17.6 exact Core-Magic metrics. BasketManager may intentionally include
// managed magic-0 positions for panel/legacy basket behavior, but Recovery
// sizing, coverage and corridor ownership remain exact Core Magic only.
bool Recovery_ReadDcaCoreMetrics(const string symbol,
                                 const long coreMagic,
                                 const eRecoveryCoreDirection dir,
                                 const bool needNetBE,
                                 double &coreLots,
                                 double &netBE)
{
   coreLots = 0.0;
   netBE = 0.0;
   long wantedType = dir == recovery_CORE_BUY ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   double weighted = 0.0;
   double signedCosts = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != symbol ||
         PositionGetInteger(POSITION_MAGIC) != coreMagic ||
         PositionGetInteger(POSITION_TYPE) != wantedType)
         continue;
      double lots = PositionGetDouble(POSITION_VOLUME);
      if(lots <= 0.0) continue;
      coreLots += lots;
      if(!needNetBE) continue;
      weighted += PositionGetDouble(POSITION_PRICE_OPEN) * lots;
      signedCosts += PositionGetDouble(POSITION_SWAP);
      ulong identifier = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
      signedCosts += Recovery_DcaPositionEntryCosts(identifier, symbol, coreMagic);
   }
   if(coreLots <= 0.0) return false;
   if(!needNetBE) return true;
   double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickSize <= 0.0 || tickValue <= 0.0) return false;
   netBE = Recovery_NetBreakevenFromCosts(weighted / coreLots,
                                           coreLots,
                                           signedCosts,
                                           tickValue,
                                           tickSize,
                                           wantedType == POSITION_TYPE_BUY);
   return netBE > 0.0;
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

void Recovery_StopTesterOnStartupBlock(const string scope)
{
   if(!MQLInfoInteger(MQL_TESTER)) return;
   Log_Error("Recovery", "Strategy Tester stopped: Recovery ACTIVE startup is not reconciled/ready (" + scope + ")");
   TesterStop();
}

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

      if(!Recovery_DcaStateAllows(RecoveryMode_, ContinueDcaAfterHedge_, cycle.state))
      {
         Log_Warn("Recovery", "dcastate" + (string)dir,
                  "Core DCA blocked by Recovery state=" + Recovery_StateName(cycle.state) +
                  "; ContinueDcaAfterHedge=" + (ContinueDcaAfterHedge_ ? "true" : "false"));
         return false;
      }
      if(!Recovery_DcaPostHedgeStableState(cycle.state))
         return true;

      bool terminalNoHedge = m_recovery->TerminalNoHedge(recoveryDir);
      if(Recovery_T1711TerminalNoHedgeDcaAllowsPure(RecoveryMode_,
                                                    ContinueDcaAfterHedge_,
                                                    terminalNoHedge))
      {
         Log_WarnEvery("Recovery", "t1711terminaldca" + (string)dir,
                       "T17.11 terminal-no-Hedge: live Hedge metrics are N/A; Core DCA continues through normal non-Hedge filters",
                       Recovery_T165WaitLogSecondsPure(RecoveryWaitLogSeconds_));
         return true;
      }

      // T17.6: the denominator and net BE use exact Core Magic, matching ARCS.
      double coreLots = cycle.coreLots;
      double coreBE   = 0.0;
      double pipSize  = Recovery_PipSizePure(Sym_IsGold(), ctx.point, ctx.digits);
      double hedgeLots = cycle.activeHedgeLots;
      double hedgeBE   = cycle.hedgeNetBE;
      bool needCoverage = MinHedgeCoveragePercent_ > 0.0;
      bool needCorridor = TargetRecoveryCorridorPips_ > 0.0;
      if(needCoverage || needCorridor)
      {
         if(!Recovery_ReadDcaCoreMetrics(_Symbol, (long)Magic, recoveryDir,
                                         needCorridor, coreLots, coreBE))
         {
            Log_Warn("Recovery", "dcacoremetric" + (string)dir,
                     "Core DCA blocked: exact Core-Magic metrics are unavailable");
            return false;
         }
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
