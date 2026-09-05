//+------------------------------------------------------------------+
//| RecoveryExecutionIdentity.mqh — T14 pure identity policy         |
//| Purpose   : deterministic request/deal/protective-SL terminal    |
//|             policy shared by ExecutionLayer and native tests.    |
//| Invariants: identity evidence may prove execution even when      |
//|             aggregate position count/volume is unchanged.        |
//|             Ambiguous strict outcomes remain fail-closed.        |
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_EXECUTION_IDENTITY_MQH
#define BD_RECOVERY_EXECUTION_IDENTITY_MQH

#include <BlackDragon/Types.mqh>

bool Recovery_ExecOpenIdentityCompletePure(const uint retcode,
                                           const bool requestIdentityMatch,
                                           const bool ownerMatch,
                                           const bool dealIdentityMatch,
                                           const bool serverOrderIdentityMatch,
                                           const bool serverOrderLive,
                                           const double observedVolume,
                                           const double targetVolume,
                                           const double volumeStep)
{
   if(retcode != TRADE_RETCODE_DONE && retcode != TRADE_RETCODE_DONE_PARTIAL)
      return false;
   if(!requestIdentityMatch || !ownerMatch || !dealIdentityMatch ||
      !serverOrderIdentityMatch || serverOrderLive)
      return false;
   if(observedVolume <= 0.0 || targetVolume <= 0.0) return false;
   double eps = volumeStep > 0.0 ? volumeStep * 0.5 : 1e-9;

   // DONE_PARTIAL is terminal only after cumulative correlated deal volume
   // proves the complete requested child. A partial server acknowledgement by
   // itself is never promoted to full command completion.
   return observedVolume + eps >= targetVolume;
}

bool Recovery_ExecStrictAmbiguousMustBlockPure(const uint retcode,
                                                const eExecReconcilePolicy policy)
{
   if(policy != EXEC_RECONCILE_FAIL_CLOSED) return false;
   return retcode == TRADE_RETCODE_TIMEOUT || retcode == TRADE_RETCODE_CONNECTION;
}

bool Recovery_ProtectiveSlIdentityPure(const bool ownerRecoveryMatch,
                                       const bool positionIdentityMatch,
                                       const long dealReason,
                                       const double programmedSl,
                                       const double durableTargetSl,
                                       const double dealPrice,
                                       const double slTolerance,
                                       const double fillTolerance,
                                       const bool confirmedModifyProof)
{
   if(!ownerRecoveryMatch || !positionIdentityMatch || dealReason != DEAL_REASON_SL)
      return false;
   if(durableTargetSl <= 0.0 || dealPrice <= 0.0 ||
      slTolerance < 0.0 || fillTolerance < 0.0)
      return false;

   bool programmedMatch = programmedSl > 0.0 &&
                          MathAbs(programmedSl - durableTargetSl) <= slTolerance + 1e-12;
   if(!programmedMatch && !confirmedModifyProof) return false;
   return MathAbs(dealPrice - durableTargetSl) <= fillTolerance + 1e-12;
}

bool Recovery_GlobalJournalReleasePure(const bool accountFlat,
                                       const bool terminalExecutionProof,
                                       const bool ambiguousOutcome)
{
   return accountFlat && terminalExecutionProof && !ambiguousOutcome;
}

#endif // BD_RECOVERY_EXECUTION_IDENTITY_MQH
