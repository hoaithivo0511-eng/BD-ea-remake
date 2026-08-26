//+------------------------------------------------------------------+
//| RecoveryT177MigrationPolicy.mqh — C5 side/policy pure locks      |
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_T177_MIGRATION_POLICY_MQH
#define BD_RECOVERY_T177_MIGRATION_POLICY_MQH

#include "RecoveryT16Config.mqh"

bool Recovery_T177OverlapCoreOnlyBlockedPure(const eRecoveryState state,
                                             const double activeHedgeLots)
{
   if(activeHedgeLots > 1e-12) return true;
   return state != recovery_CORE_ONLY && state != recovery_ARMED &&
          state != recovery_COMPLETED;
}

// T17.11: terminal-no-Hedge is the one Recovery-owned topology where CORE_ONLY
// may become Core-only again. Keep the T17.7 policy unchanged for every other
// state, require the authoritative terminal predicate, honor the user's
// ContinueDcaAfterHedge opt-out, and defensively reject any live Hedge lot.
bool Recovery_T1711OverlapCoreOnlyBlockedPure(const eRecoveryState state,
                                              const double activeHedgeLots,
                                              const bool terminalNoHedge,
                                              const bool continueAfterHedge)
{
   if(terminalNoHedge && continueAfterHedge && activeHedgeLots <= 1e-12)
      return false;
   return Recovery_T177OverlapCoreOnlyBlockedPure(state, activeHedgeLots);
}

#endif // BD_RECOVERY_T177_MIGRATION_POLICY_MQH
