//+------------------------------------------------------------------+
//| RecoveryT1714InterleavePolicy.mqh — exact protective refresh     |
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_T1714_INTERLEAVE_POLICY_MQH
#define BD_RECOVERY_T1714_INTERLEAVE_POLICY_MQH

enum eRecoveryT1714LayerRefresh
{
   recovery_T1714_REFRESH_UNCHANGED = 0,
   recovery_T1714_REFRESH_APPLY = 1,
   recovery_T1714_REFRESH_RECONCILE = 2
};

eRecoveryT1714LayerRefresh Recovery_T1714LayerRefreshPure(
   const long persistedUnits,
   const long liveUnits,
   const long provenProtectiveCloseUnits)
{
   if(persistedUnits < 0 || liveUnits < 0 || liveUnits > persistedUnits ||
      provenProtectiveCloseUnits < 0)
      return recovery_T1714_REFRESH_RECONCILE;

   long observedCloseUnits = persistedUnits - liveUnits;
   if(observedCloseUnits == 0)
      return recovery_T1714_REFRESH_UNCHANGED;
   if(provenProtectiveCloseUnits != observedCloseUnits)
      return recovery_T1714_REFRESH_RECONCILE;
   return recovery_T1714_REFRESH_APPLY;
}

#endif // BD_RECOVERY_T1714_INTERLEAVE_POLICY_MQH
