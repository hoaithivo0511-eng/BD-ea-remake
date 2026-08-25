//+------------------------------------------------------------------+
//| RecoveryT179RealTpPolicy.mqh — pure REAL-TP interleave policy    |
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_T179_REAL_TP_POLICY_MQH
#define BD_RECOVERY_T179_REAL_TP_POLICY_MQH

enum eRecoveryT179RealTpProof
{
   RECOVERY_T179_TP_EXTERNAL = 0,
   RECOVERY_T179_TP_PREOWNERSHIP,
   RECOVERY_T179_TP_DURABLE_EPOCH
};

bool Recovery_T179StrictBrokerTpProofPure(const bool realMode,
                                          const bool configuredTp,
                                          const bool ownerCore,
                                          const bool reasonTp,
                                          const double programmedTp,
                                          const double dealPrice,
                                          const double fillTolerance)
{
   if(!realMode || !configuredTp || !ownerCore || !reasonTp) return false;
   if(programmedTp <= 0.0 || dealPrice <= 0.0 || fillTolerance < 0.0) return false;
   return MathAbs(dealPrice - programmedTp) <= fillTolerance + 1e-12;
}

eRecoveryT179RealTpProof Recovery_T179ClassifyBrokerTpPure(
   const bool strictProof,
   const bool recoveryOwnsSide,
   const bool epochActive,
   const bool epochTargetMatches,
   const bool epochContainsPosition)
{
   if(!strictProof) return RECOVERY_T179_TP_EXTERNAL;
   if(!recoveryOwnsSide) return RECOVERY_T179_TP_PREOWNERSHIP;
   if(epochActive && epochTargetMatches && epochContainsPosition)
      return RECOVERY_T179_TP_DURABLE_EPOCH;
   return RECOVERY_T179_TP_EXTERNAL;
}

bool Recovery_T179SettlementStartsPure(const bool epochActive,
                                       const bool alreadySettling,
                                       const bool priceHit,
                                       const bool expectedTpCallback)
{
   return epochActive && !alreadySettling && (priceHit || expectedTpCallback);
}

bool Recovery_T179BlocksSameSideAddPure(const bool persistenceFault,
                                        const bool epochSettling)
{
   return persistenceFault || epochSettling;
}

bool Recovery_T179SettlementCompletePure(const bool epochActive,
                                         const bool epochSettling,
                                         const long coreUnits,
                                         const long recoveryUnits,
                                         const bool reconcileHold)
{
   return epochActive && epochSettling && coreUnits <= 0 && recoveryUnits <= 0 &&
          !reconcileHold;
}

bool Recovery_T179ModifyCandidatePure(const ulong requestedTicket,
                                      const bool selected,
                                      const ulong selectedTicket,
                                      const bool symbolMatches,
                                      const bool ownerMatches,
                                      const bool typeMatches,
                                      const double liveVolume)
{
   return requestedTicket != 0 && selected && selectedTicket == requestedTicket &&
          symbolMatches && ownerMatches && typeMatches && liveVolume > 0.0;
}

#endif // BD_RECOVERY_T179_REAL_TP_POLICY_MQH

