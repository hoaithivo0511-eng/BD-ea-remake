//+------------------------------------------------------------------+
//| RecoveryT163Policy.mqh — pure T16.3 liveness scheduling policy   |
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_T163_POLICY_MQH
#define BD_RECOVERY_T163_POLICY_MQH

#include "RecoveryTypes.mqh"

bool Recovery_T163DeferredLockYieldPure(const bool recoveryConsumed,
                                        const bool deterministicLocalWait,
                                        const bool executionPending,
                                        const bool executionReconcile)
{
   return recoveryConsumed && deterministicLocalWait &&
          !executionPending && !executionReconcile;
}

bool Recovery_T1711TerminalNoHedgePure(const int generationCount,
                                       const int maxGenerations,
                                       const long coreUnits,
                                       const long hedgeUnits,
                                       const bool terminalPhase)
{
   return terminalPhase && maxGenerations >= 1 &&
          generationCount >= maxGenerations &&
          coreUnits > 0 && hedgeUnits <= 0;
}

bool Recovery_T163MaxedNoHedgePure(const int generationCount,
                                   const int maxGenerations,
                                   const long coreUnits,
                                   const long hedgeUnits,
                                   const bool terminalPhase)
{
   return Recovery_T1711TerminalNoHedgePure(generationCount,
                                            maxGenerations,
                                            coreUnits,
                                            hedgeUnits,
                                            terminalPhase);
}

// Compatibility view only. Internal ARCS durable phase is not rewritten.
// REHEDGE_PENDING is DCA-stable but Overlap-deferred; HEDGE_LOCKED is stable
// for both DCA and coordinated Overlap. StartGeneration keeps the hard Max cap.
eRecoveryState Recovery_T163SchedulingStatePure(const eRecoveryState baseState,
                                                 const bool deferredLockYield,
                                                 const bool maxedNoHedge)
{
   if(deferredLockYield) return recovery_REHEDGE_PENDING;
   if(maxedNoHedge) return recovery_HEDGE_LOCKED;
   return baseState;
}

#endif // BD_RECOVERY_T163_POLICY_MQH
