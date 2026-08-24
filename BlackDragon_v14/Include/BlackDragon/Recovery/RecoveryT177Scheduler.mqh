//+------------------------------------------------------------------+
//| RecoveryT177Scheduler.mqh — T17.7 C1 scheduler disposition      |
//| WAIT/no-effect yields Strategy; mutation/pending/reconcile owns. |
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_T177_SCHEDULER_MQH
#define BD_RECOVERY_T177_SCHEDULER_MQH

#include "RecoveryTypes.mqh"

enum eRecoveryDriveDisposition
{
   RECOVERY_DRIVE_NO_EFFECT = 0,
   RECOVERY_DRIVE_WAIT,
   RECOVERY_DRIVE_MUTATED,
   RECOVERY_DRIVE_PENDING,
   RECOVERY_DRIVE_RECONCILE
};

eRecoveryDriveDisposition Recovery_T177ClassifyDrivePure(const bool legacyConsumed,
                                                         const bool semanticChanged,
                                                         const bool pending,
                                                         const bool reconcile)
{
   if(reconcile) return RECOVERY_DRIVE_RECONCILE;
   if(pending) return RECOVERY_DRIVE_PENDING;
   if(semanticChanged) return RECOVERY_DRIVE_MUTATED;
   if(!legacyConsumed) return RECOVERY_DRIVE_NO_EFFECT;
   return RECOVERY_DRIVE_WAIT;
}

bool Recovery_T177ConsumesStrategyTickPure(const eRecoveryDriveDisposition d)
{
   return d == RECOVERY_DRIVE_MUTATED ||
          d == RECOVERY_DRIVE_PENDING ||
          d == RECOVERY_DRIVE_RECONCILE;
}

bool Recovery_T177AllowsOtherModulesPure(const eRecoveryDriveDisposition d)
{
   return d == RECOVERY_DRIVE_NO_EFFECT || d == RECOVERY_DRIVE_WAIT;
}

string Recovery_T177DispositionNameVi(const eRecoveryDriveDisposition d)
{
   switch(d)
   {
      case RECOVERY_DRIVE_NO_EFFECT: return "KHÔNG CÓ VIỆC";
      case RECOVERY_DRIVE_WAIT:      return "CHỜ";
      case RECOVERY_DRIVE_MUTATED:   return "ĐÃ THAY ĐỔI";
      case RECOVERY_DRIVE_PENDING:   return "ĐANG CHỜ KHỚP";
      case RECOVERY_DRIVE_RECONCILE: return "LỖI / ĐỐI SOÁT";
   }
   return "KHÔNG RÕ";
}

#endif // BD_RECOVERY_T177_SCHEDULER_MQH
