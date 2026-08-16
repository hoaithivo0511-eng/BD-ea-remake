//+------------------------------------------------------------------+
//| RecoveryDca.mqh — T7 Continue-DCA + corridor/coverage gate       |
//| Invariants: filter-only integration; legacy TryGridAdd remains   |
//|             the sole Core DCA order-generation mechanism.        |
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_DCA_MQH
#define BD_RECOVERY_DCA_MQH

#include "RecoveryEngine.mqh"
#include <BlackDragon/BasketManager.mqh>

input group "17 — Recovery DCA / Corridor"
input bool   ContinueDcaAfterHedge_       = false; // OFF = lock DCA after hedge becomes active
input double MinHedgeCoveragePercent_     = 0.0;   // 0 = disabled
input double TargetRecoveryCorridorPips_  = 0.0;   // 0 = disabled

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
      if(m_recovery == NULL || m_basket == NULL) return false;

      eRecoveryCoreDirection recoveryDir =
         dir == BD_DIR_BUY ? recovery_CORE_BUY : recovery_CORE_SELL;
      SRecoveryCycle cycle;
      m_recovery.GetCycle(recoveryDir, cycle);

      double coreLots = dir == BD_DIR_BUY ? m_basket.buy.totalLots : m_basket.sell.totalLots;
      double coreBE   = dir == BD_DIR_BUY ? m_basket.buy.breakeven : m_basket.sell.breakeven;
      double pipSize  = Recovery_PipSizePure(Sym_IsGold(), ctx.point, ctx.digits);

      return Recovery_DcaGateAllows(RecoveryMode_,
                                    ContinueDcaAfterHedge_,
                                    cycle.state,
                                    MinHedgeCoveragePercent_,
                                    TargetRecoveryCorridorPips_,
                                    recoveryDir,
                                    coreLots,
                                    coreBE,
                                    cycle.activeHedgeLots,
                                    cycle.hedgeNetBE,
                                    pipSize);
   }
};

#endif // BD_RECOVERY_DCA_MQH
