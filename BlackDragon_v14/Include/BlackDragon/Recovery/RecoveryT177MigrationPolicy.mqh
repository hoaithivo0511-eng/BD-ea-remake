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

#endif // BD_RECOVERY_T177_MIGRATION_POLICY_MQH
