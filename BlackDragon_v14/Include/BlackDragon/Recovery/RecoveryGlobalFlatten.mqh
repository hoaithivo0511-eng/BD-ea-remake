//+------------------------------------------------------------------+
//| RecoveryGlobalFlatten.mqh — T11 global-close lifecycle latch     |
//| Purpose   : transient hand-off between T8 coordinator and T3/T9  |
//|             registry observation after an account-wide flatten.  |
//| Invariants: no trade API calls; latch is released only after     |
//|             COMPLETED state is durably flushed.                  |
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_GLOBAL_FLATTEN_MQH
#define BD_RECOVERY_GLOBAL_FLATTEN_MQH

bool     g_recoveryGlobalFlattenRequested = false;
datetime g_recoveryGlobalFlattenRequestedAt = 0;

bool Recovery_GlobalFlattenReadyPure(const int livePositions,
                                     const bool executionPending)
{
   return livePositions == 0 && !executionPending;
}

void Recovery_RequestGlobalFlattenFinalization(const datetime now)
{
   g_recoveryGlobalFlattenRequested = true;
   g_recoveryGlobalFlattenRequestedAt = now;
}

bool Recovery_GlobalFlattenFinalizationRequested()
{
   return g_recoveryGlobalFlattenRequested;
}

datetime Recovery_GlobalFlattenRequestedAt()
{
   return g_recoveryGlobalFlattenRequestedAt;
}

void Recovery_ClearGlobalFlattenFinalization()
{
   g_recoveryGlobalFlattenRequested = false;
   g_recoveryGlobalFlattenRequestedAt = 0;
}

#endif // BD_RECOVERY_GLOBAL_FLATTEN_MQH
