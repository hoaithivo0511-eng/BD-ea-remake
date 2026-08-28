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

// State is only one part of Overlap admission. A state that can be coordinated
// still needs a live capability proof that Recovery is ready and every durable,
// execution-journal and coordinator mutation channel is quiet. BUILDING is a
// long-lived wait state between Hedge children, so it is safe to coordinate only
// under that proof; an in-flight child remains deferred by the pending flags.
eRecoveryOverlapPolicy Recovery_OverlapCapabilityPolicyPure(
   const eRecoveryState state,
   const bool activeReady,
   const bool recoveryMutationPending,
   const bool journalMutationPending,
   const bool coordinatorPending)
{
   if(!activeReady || recoveryMutationPending || journalMutationPending ||
      coordinatorPending)
      return recovery_OVERLAP_DEFER;

   if(state == recovery_CORE_ONLY || state == recovery_COMPLETED)
      return recovery_OVERLAP_BYPASS;
   if(state == recovery_ARMED ||
      state == recovery_HEDGE_BUILDING ||
      state == recovery_HEDGE_ACTIVE ||
      state == recovery_HEDGE_LOCKED)
      return recovery_OVERLAP_COORDINATE;
   return recovery_OVERLAP_DEFER;
}

// Compatibility oracle for historical unit tests. Runtime callers must use the
// capability policy above and provide live mutation facts.
eRecoveryOverlapPolicy Recovery_OverlapPolicyPure(const eRecoveryState state)
{
   if(state == recovery_CORE_ONLY || state == recovery_COMPLETED)
      return recovery_OVERLAP_BYPASS;
   if(state == recovery_ARMED || state == recovery_HEDGE_ACTIVE ||
      state == recovery_HEDGE_LOCKED)
      return recovery_OVERLAP_COORDINATE;
   return recovery_OVERLAP_DEFER;
}

long Recovery_OverlapHardCapUnitsPure(const long projectedCoreUnits,
                                      const double hardCapPercent)
{
   if(projectedCoreUnits <= 0 || hardCapPercent <= 0.0) return 0;
   return (long)MathFloor((double)projectedCoreUnits * hardCapPercent /
                          100.0 + 1e-9);
}

bool Recovery_OverlapRetainedWithinHardCapPure(const long projectedCoreUnits,
                                               const long retainedHedgeUnits,
                                               const double hardCapPercent)
{
   if(projectedCoreUnits < 0 || retainedHedgeUnits < 0) return false;
   if(hardCapPercent <= 0.0) return true;
   return retainedHedgeUnits <=
          Recovery_OverlapHardCapUnitsPure(projectedCoreUnits, hardCapPercent);
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
