//+------------------------------------------------------------------+
//| RecoveryGlobalFlatten.mqh — T12 atomic global-close gates     |
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

// T12: a confirmed account-wide flatten is a new known-empty broker
// boundary. It may recover ACTIVE from an earlier runtime
// reconcile/fail-closed state, but never through persistence or
// execution ambiguity.
bool Recovery_GlobalFlattenCanFinalizePure(const int livePositions,
                                            const bool executionPending,
                                            const bool persistenceBlocked,
                                            const bool buyReconcileRequired,
                                            const bool sellReconcileRequired)
{
   return Recovery_GlobalFlattenReadyPure(livePositions, executionPending) &&
          !persistenceBlocked &&
          !buyReconcileRequired &&
          !sellReconcileRequired;
}

// Roll exactly once when a non-terminal slot is terminalized. If a
// persistence retry re-enters with COMPLETED already visible, keep
// the serial stable so T5/T6 cannot be reset repeatedly.
int Recovery_GlobalFlattenNextSerialPure(const int currentSerial,
                                         const bool alreadyCompleted)
{
   int serial = currentSerial < 1 ? 1 : currentSerial;
   return alreadyCompleted ? serial : serial + 1;
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
