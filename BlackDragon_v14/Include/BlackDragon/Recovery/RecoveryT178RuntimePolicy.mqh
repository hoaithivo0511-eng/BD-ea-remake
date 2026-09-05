//+------------------------------------------------------------------+
//| RecoveryT178RuntimePolicy.mqh — T17.8 P1 runtime fix policies    |
//| Scope: ACTIVE no-op starvation + expected broker REAL TP.        |
//| Hedge coverage/input semantics are intentionally unchanged.      |
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_T178_RUNTIME_POLICY_MQH
#define BD_RECOVERY_T178_RUNTIME_POLICY_MQH

enum eRecoveryT178RealTpDisposition
{
   RECOVERY_T178_REAL_TP_EXTERNAL = 0,
   RECOVERY_T178_REAL_TP_BYPASS_PREOWNERSHIP,
   RECOVERY_T178_REAL_TP_COORDINATE_FULL_SIDE
};

bool Recovery_T178ActiveTpWaitNoMutationPure(const bool activePhase,
                                             const bool layerValid,
                                             const long liveUnits,
                                             const long persistedOpenedUnits,
                                             const long persistedRemainingUnits,
                                             const bool tpHit)
{
   return activePhase && layerValid && liveUnits > 0 &&
          liveUnits == persistedOpenedUnits &&
          liveUnits == persistedRemainingUnits &&
          !tpHit;
}

// C1 must classify trade/broker semantics, not persistence bookkeeping.
// If the wrapped engine consumed the tick but nothing except persistence changed,
// there is no pending/reconcile work and other Strategy modules must continue.
bool Recovery_T178PersistenceOnlyYieldPure(const bool legacyConsumed,
                                           const bool semanticChangedExcludingPersistence,
                                           const bool pending,
                                           const bool reconcile)
{
   if(!legacyConsumed) return false;
   if(reconcile || pending || semanticChangedExcludingPersistence) return false;
   return true;
}

bool Recovery_T178ExpectedCoreRealTpPure(const bool realTpMode,
                                         const bool configuredTpEnabled,
                                         const bool exactCoreOwner,
                                         const bool reasonIsTp,
                                         const double programmedTp,
                                         const double dealPrice,
                                         const double fillTolerance,
                                         const bool liveCohortMatches)
{
   if(!realTpMode || !configuredTpEnabled || !exactCoreOwner || !reasonIsTp)
      return false;
   if(programmedTp <= 0.0 || dealPrice <= 0.0 || fillTolerance < 0.0)
      return false;
   if(MathAbs(dealPrice - programmedTp) > fillTolerance + 1e-12)
      return false;
   return liveCohortMatches;
}

eRecoveryT178RealTpDisposition Recovery_T178RealTpDispositionPure(const bool expectedRealTp,
                                                                   const bool recoveryNeedsCoordination)
{
   if(!expectedRealTp) return RECOVERY_T178_REAL_TP_EXTERNAL;
   return recoveryNeedsCoordination ? RECOVERY_T178_REAL_TP_COORDINATE_FULL_SIDE
                                    : RECOVERY_T178_REAL_TP_BYPASS_PREOWNERSHIP;
}

#endif // BD_RECOVERY_T178_RUNTIME_POLICY_MQH
