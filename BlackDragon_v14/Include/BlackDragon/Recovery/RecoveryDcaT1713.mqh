//+------------------------------------------------------------------+
//| RecoveryDcaT1713.mqh — non-exclusive Core DCA admission         |
//| Keeps RecoveryDca.mqh byte-identical; overrides only Allow().    |
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_DCA_T1713_MQH
#define BD_RECOVERY_DCA_T1713_MQH

#include "RecoveryT1713ConcurrencyPolicy.mqh"

#define private protected
#define CRecoveryDcaFilter CRecoveryDcaFilterT1712Base
#include "RecoveryDca.mqh"
#undef CRecoveryDcaFilter
#undef private

class CRecoveryDcaFilter : public CRecoveryDcaFilterT1712Base
{
public:
   CRecoveryDcaFilter(CRecoveryEngine *recovery, CBasketManager *basket)
      : CRecoveryDcaFilterT1712Base(recovery, basket) {}

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

      if(!Recovery_T1713CoreGrowthStateAllowsPure(RecoveryMode_,
                                                   ContinueDcaAfterHedge_,
                                                   cycle.state))
      {
         Log_WarnEvery("Recovery", "t1713dcastate" + (string)dir,
                       "T17.13 Core DCA blocked by mutating/protected Recovery state=" +
                       Recovery_StateName(cycle.state) +
                       "; ContinueDcaAfterHedge=" +
                       (ContinueDcaAfterHedge_ ? "true" : "false"),
                       Recovery_T165WaitLogSecondsPure(RecoveryWaitLogSeconds_));
         return false;
      }

      // CORE_ONLY/ARMED are exact legacy admission. BUILDING and stable Hedge
      // states below may continue only after any explicitly configured
      // coverage/corridor constraints are satisfied.
      if(!Recovery_T1713CoreGrowthUsesHedgeMetricsPure(cycle.state))
         return true;

      bool terminalNoHedge = m_recovery.TerminalNoHedge(recoveryDir);
      if(Recovery_DcaPostHedgeStableState(cycle.state) &&
         Recovery_T1711TerminalNoHedgeDcaAllowsPure(RecoveryMode_,
                                                    ContinueDcaAfterHedge_,
                                                    terminalNoHedge))
      {
         Log_WarnEvery("Recovery", "t1711terminaldca" + (string)dir,
                       "T17.11 terminal-no-Hedge: live Hedge metrics are N/A; Core DCA continues through normal non-Hedge filters",
                       Recovery_T165WaitLogSecondsPure(RecoveryWaitLogSeconds_));
         return true;
      }

      bool needCoverage = MinHedgeCoveragePercent_ > 0.0;
      bool needCorridor = TargetRecoveryCorridorPips_ > 0.0;
      if(!needCoverage && !needCorridor) return true;

      double coreLots = cycle.coreLots;
      double coreBE = 0.0;
      double pipSize = Recovery_PipSizePure(Sym_IsGold(), ctx.point, ctx.digits);
      double hedgeLots = cycle.activeHedgeLots;
      double hedgeBE = cycle.hedgeNetBE;

      if(!Recovery_ReadDcaCoreMetrics(_Symbol, (long)Magic, recoveryDir,
                                      needCorridor, coreLots, coreBE))
      {
         Log_WarnEvery("Recovery", "t1713dcacoremetric" + (string)dir,
                       "T17.13 Core DCA blocked: exact Core-Magic metrics unavailable",
                       Recovery_T165WaitLogSecondsPure(RecoveryWaitLogSeconds_));
         return false;
      }
      if(!Recovery_ReadDcaHedgeMetrics(_Symbol, RecoveryMagic_, recoveryDir,
                                       needCorridor, hedgeLots, hedgeBE))
      {
         Log_WarnEvery("Recovery", "t1713dcahedgemetric" + (string)dir,
                       "T17.13 Core DCA blocked: configured coverage/corridor requires live Hedge metrics",
                       Recovery_T165WaitLogSecondsPure(RecoveryWaitLogSeconds_));
         return false;
      }

      if(!Recovery_DcaCoverageAllows(MinHedgeCoveragePercent_, coreLots, hedgeLots))
      {
         Log_WarnEvery("Recovery", "t1713dcacoverage" + (string)dir,
                       "T17.13 Core DCA waits for configured minimum Hedge coverage",
                       Recovery_T165WaitLogSecondsPure(RecoveryWaitLogSeconds_));
         return false;
      }
      if(!Recovery_DcaCorridorAllows(TargetRecoveryCorridorPips_, recoveryDir,
                                     coreBE, hedgeBE, pipSize))
      {
         Log_WarnEvery("Recovery", "t1713dcacorridor" + (string)dir,
                       "T17.13 Core DCA stopped by configured Recovery corridor",
                       Recovery_T165WaitLogSecondsPure(RecoveryWaitLogSeconds_));
         return false;
      }
      return true;
   }
};

#endif // BD_RECOVERY_DCA_T1713_MQH
