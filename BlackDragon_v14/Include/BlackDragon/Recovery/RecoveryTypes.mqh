//+------------------------------------------------------------------+
//| RecoveryTypes.mqh — Adaptive Recovery Hedge T1 foundation        |
//| Purpose   : Recovery mode/config types + initialization guards.  |
//| Invariants: T1 sends NO Recovery trade request.                  |
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_TYPES_MQH
#define BD_RECOVERY_TYPES_MQH

#include <BlackDragon/Config.mqh>
#include "RecoveryMath.mqh"

enum eRecoveryMode
{
   recovery_OFF    = 0,
   recovery_SHADOW = 1,
   recovery_ACTIVE = 2
};

enum eRecoveryCoreDirection
{
   recovery_CORE_BUY  = 0,
   recovery_CORE_SELL = 1
};

// T1 exposes only foundation inputs. Later task slices add execution/ledger
// settings after their contracts are implemented and verified.
input group "16 — Adaptive Recovery Hedge"
input eRecoveryMode RecoveryMode_          = recovery_OFF; // OFF / SHADOW / ACTIVE
input long          RecoveryMagic_         = 20260807;     // Must differ from Core Magic when enabled
input int           RecoveryStartAfterDca_ = 5;            // Initial Core order is excluded

struct SRecoveryFoundationConfig
{
   eRecoveryMode mode;
   long          recoveryMagic;
   int           startAfterDca;
};

void Recovery_LoadFoundationConfig(SRecoveryFoundationConfig &cfg)
{
   cfg.mode          = RecoveryMode_;
   cfg.recoveryMagic = RecoveryMagic_;
   cfg.startAfterDca = RecoveryStartAfterDca_;
}

bool Recovery_ModeValid(const eRecoveryMode mode)
{
   return mode == recovery_OFF || mode == recovery_SHADOW || mode == recovery_ACTIVE;
}

// Pure validation so it can be unit-tested without broker mutation.
// OFF is deliberately permissive: legacy v14.9 must initialize unchanged even
// on netting accounts or with unused Recovery inputs that would be invalid if
// Recovery were enabled.
bool Recovery_ValidateFoundation(const eRecoveryMode mode,
                                 const long coreMagic,
                                 const long recoveryMagic,
                                 const int startAfterDca,
                                 const long marginMode,
                                 string &why)
{
   why = "";
   if(!Recovery_ModeValid(mode))
   {
      why = "RecoveryMode_ invalid";
      return false;
   }

   if(mode == recovery_OFF) return true;

   if(recoveryMagic <= 0)
   {
      why = "RecoveryMagic_ must be > 0 when Recovery is enabled";
      return false;
   }
   if(recoveryMagic == coreMagic)
   {
      why = "RecoveryMagic_ must differ from Core Magic";
      return false;
   }
   if(startAfterDca < 0)
   {
      why = "RecoveryStartAfterDca_ must be >= 0";
      return false;
   }
   if(mode == recovery_ACTIVE && marginMode != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
   {
      why = "Recovery ACTIVE requires ACCOUNT_MARGIN_MODE_RETAIL_HEDGING";
      return false;
   }
   return true;
}

#endif // BD_RECOVERY_TYPES_MQH
