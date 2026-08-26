//+------------------------------------------------------------------+
//| RecoveryT1713ConcurrencyPolicy.mqh                               |
//| Non-exclusive Core growth while Recovery is read-only.           |
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_T1713_CONCURRENCY_POLICY_MQH
#define BD_RECOVERY_T1713_CONCURRENCY_POLICY_MQH

#include "RecoveryTypes.mqh"

// T17.13 owner contract: ContinueDcaAfterHedge_ is the existing switch for
// Core growth while Recovery owns the side. Read-only BUILDING/ACTIVE/LOCKED
// states may yield to DCA/Core-Pyramid ADD; submitted close/protect/reconcile
// states remain fail-closed. No persisted enum values are changed.
bool Recovery_T1713CoreGrowthStateAllowsPure(const eRecoveryMode mode,
                                              const bool continueAfterHedge,
                                              const eRecoveryState state)
{
   if(mode != recovery_ACTIVE) return true;
   if(state == recovery_CORE_ONLY || state == recovery_ARMED) return true;
   if(!continueAfterHedge) return false;
   return state == recovery_HEDGE_BUILDING ||
          state == recovery_HEDGE_ACTIVE ||
          state == recovery_HEDGE_LOCKED ||
          state == recovery_REHEDGE_PENDING;
}

bool Recovery_T1713CoreGrowthUsesHedgeMetricsPure(const eRecoveryState state)
{
   return state == recovery_HEDGE_BUILDING ||
          state == recovery_HEDGE_ACTIVE ||
          state == recovery_HEDGE_LOCKED ||
          state == recovery_REHEDGE_PENDING;
}

#endif // BD_RECOVERY_T1713_CONCURRENCY_POLICY_MQH
