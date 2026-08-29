//+------------------------------------------------------------------+
//| RecoveryT1717StopLivenessPolicy.mqh                              |
//| Pure authority rules for concurrent ARCS SL and verified flat.   |
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_T1717_STOP_LIVENESS_POLICY_MQH
#define BD_RECOVERY_T1717_STOP_LIVENESS_POLICY_MQH

enum eRecoveryT1717CoordinatorOwner
{
   RECOVERY_T1717_OWNER_NONE = 0,
   RECOVERY_T1717_OWNER_SIDE = 1,
   RECOVERY_T1717_OWNER_ACCOUNT = 2
};

eRecoveryT1717CoordinatorOwner Recovery_T1717CoordinatorOwnerPure(
   const bool accountWidePending,
   const bool sideCycleActive)
{
   if(accountWidePending) return RECOVERY_T1717_OWNER_ACCOUNT;
   if(sideCycleActive) return RECOVERY_T1717_OWNER_SIDE;
   return RECOVERY_T1717_OWNER_NONE;
}

bool Recovery_T1717ExpectedArcsSlBypassPure(
   const bool arcsActive,
   const eRecoveryT1717CoordinatorOwner owner,
   const bool exactExpectedSlProof)
{
   return arcsActive && owner != RECOVERY_T1717_OWNER_ACCOUNT &&
          exactExpectedSlProof;
}

bool Recovery_T1717VerifiedAccountFlatResetPure(
   const bool accountGuardCompleted,
   const int accountPositions,
   const bool executionPending,
   const bool recoveryCoordinatorBlocking)
{
   return accountGuardCompleted && accountPositions == 0 &&
          !executionPending && !recoveryCoordinatorBlocking;
}

bool Recovery_T1717RelatchAccountGuardPure(
   const bool accountGuardCompleted,
   const bool overlapResetSucceeded)
{
   return accountGuardCompleted && !overlapResetSucceeded;
}

#endif // BD_RECOVERY_T1717_STOP_LIVENESS_POLICY_MQH

