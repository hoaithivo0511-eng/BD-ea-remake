//+------------------------------------------------------------------+
//| RecoveryMutationPolicy.mqh — T13 side-mutation/Overlap policy    |
//| Pure policy only: no broker API, persistence, or global writes.  |
//| Verification candidate: T13 hardened lifecycle final gate.       |
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_MUTATION_POLICY_MQH
#define BD_RECOVERY_MUTATION_POLICY_MQH

#include "RecoveryTypes.mqh"

enum eRecoveryOverlapPolicy
{
   recovery_OVERLAP_BYPASS = 0,
   recovery_OVERLAP_COORDINATE,
   recovery_OVERLAP_DEFER
};

// CORE_ONLY/COMPLETED have no active Recovery topology to protect.
// ARMED/HEDGE_ACTIVE/HEDGE_LOCKED are stable enough to coordinate a Core trim.
// All mutation/pause/reconcile states defer Overlap until Recovery is stable.
eRecoveryOverlapPolicy Recovery_OverlapPolicyPure(const eRecoveryState state)
{
   if(state == recovery_CORE_ONLY || state == recovery_COMPLETED)
      return recovery_OVERLAP_BYPASS;
   if(state == recovery_ARMED ||
      state == recovery_HEDGE_ACTIVE ||
      state == recovery_HEDGE_LOCKED)
      return recovery_OVERLAP_COORDINATE;
   return recovery_OVERLAP_DEFER;
}

bool Recovery_SideMutationStableStatePure(const eRecoveryState state)
{
   return state == recovery_CORE_ONLY ||
          state == recovery_ARMED ||
          state == recovery_HEDGE_ACTIVE ||
          state == recovery_HEDGE_LOCKED ||
          state == recovery_COMPLETED;
}

#endif // BD_RECOVERY_MUTATION_POLICY_MQH
