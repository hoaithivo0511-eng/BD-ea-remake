//+------------------------------------------------------------------+
//| RecoveryStateMachine.mqh — T3 pure FSM/metric rules              |
//| Invariants: no broker mutation, no global state, deterministic.  |
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_STATE_MACHINE_MQH
#define BD_RECOVERY_STATE_MACHINE_MQH

#include "RecoveryTypes.mqh"

bool Recovery_StateTransitionAllowed(const eRecoveryState fromState,
                                     const eRecoveryState toState)
{
   if(fromState == toState) return false;

   // Safety exits are legal from every non-terminal state. GLOBAL_STOP is
   // terminal except for cleanup completion; COMPLETED may only start a new
   // logical Core cycle.
   if(fromState != recovery_COMPLETED && fromState != recovery_GLOBAL_STOP)
   {
      if(toState == recovery_PAUSE_SOFT ||
         toState == recovery_PAUSE_HARD ||
         toState == recovery_RECONCILE_REQUIRED ||
         toState == recovery_GLOBAL_STOP ||
         toState == recovery_COMPLETED)
         return true;
   }

   switch(fromState)
   {
      case recovery_CORE_ONLY:
         return toState == recovery_ARMED;

      case recovery_ARMED:
         return toState == recovery_HEDGE_BUILDING;

      case recovery_HEDGE_BUILDING:
         return toState == recovery_HEDGE_ACTIVE;

      case recovery_HEDGE_ACTIVE:
         return toState == recovery_HEDGE_TP_PENDING;

      case recovery_HEDGE_TP_PENDING:
         return toState == recovery_CORE_CLOSE_PENDING;

      case recovery_CORE_CLOSE_PENDING:
         return toState == recovery_HEDGE_LOCK_PENDING;

      case recovery_HEDGE_LOCK_PENDING:
         return toState == recovery_HEDGE_LOCKED;

      case recovery_HEDGE_LOCKED:
         return toState == recovery_REHEDGE_PENDING;

      case recovery_REHEDGE_PENDING:
         return toState == recovery_HEDGE_BUILDING;

      case recovery_PAUSE_SOFT:
         return toState == recovery_ARMED ||
                toState == recovery_HEDGE_ACTIVE ||
                toState == recovery_HEDGE_LOCKED ||
                toState == recovery_REHEDGE_PENDING;

      case recovery_PAUSE_HARD:
      case recovery_RECONCILE_REQUIRED:
         return false; // only safety escalation is handled above

      case recovery_GLOBAL_STOP:
         return toState == recovery_COMPLETED;

      case recovery_COMPLETED:
         return toState == recovery_CORE_ONLY; // next Core series reuses the slot
   }
   return false;
}

bool Recovery_AdverseGapHitTicks(const eRecoveryCoreDirection dir,
                                 const long anchorTicks,
                                 const long bidTicks,
                                 const long askTicks,
                                 const long gapTicks)
{
   if(anchorTicks <= 0 || bidTicks <= 0 || askTicks <= 0 || gapTicks < 0)
      return false;
   if(gapTicks == 0) return true;

   if(dir == recovery_CORE_BUY)
      return bidTicks <= anchorTicks - gapTicks; // SELL hedge would execute at bid
   return askTicks >= anchorTicks + gapTicks;    // BUY hedge would execute at ask
}

double Recovery_CoveragePercent(const double currentCoreLots,
                                const double activeRecoveryHedgeLots)
{
   if(currentCoreLots <= 0.0 || activeRecoveryHedgeLots <= 0.0) return 0.0;
   return activeRecoveryHedgeLots / currentCoreLots * 100.0;
}

double Recovery_CorridorPrice(const eRecoveryCoreDirection dir,
                              const double coreNetBE,
                              const double hedgeNetBE)
{
   if(coreNetBE <= 0.0 || hedgeNetBE <= 0.0) return 0.0;
   if(dir == recovery_CORE_BUY)
      return hedgeNetBE - coreNetBE;
   return coreNetBE - hedgeNetBE;
}

int Recovery_HedgeDirection(const eRecoveryCoreDirection coreDir)
{
   return coreDir == recovery_CORE_BUY ? 1 : 0; // 0 BUY, 1 SELL
}

#endif // BD_RECOVERY_STATE_MACHINE_MQH
