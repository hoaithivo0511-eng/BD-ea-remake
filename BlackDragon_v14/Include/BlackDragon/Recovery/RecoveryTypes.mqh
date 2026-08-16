//+------------------------------------------------------------------+
//| RecoveryTypes.mqh — Adaptive Recovery Hedge foundation           |
//| Purpose   : Recovery mode/state/config types + init guards.      |
//| Invariants: Types/config only; no trade API calls.               |
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

enum eRecoveryState
{
   recovery_CORE_ONLY = 0,
   recovery_ARMED,
   recovery_HEDGE_BUILDING,
   recovery_HEDGE_ACTIVE,
   recovery_HEDGE_TP_PENDING,
   recovery_CORE_CLOSE_PENDING,
   recovery_HEDGE_LOCK_PENDING,
   recovery_HEDGE_LOCKED,
   recovery_REHEDGE_PENDING,
   recovery_PAUSE_SOFT,
   recovery_PAUSE_HARD,
   recovery_RECONCILE_REQUIRED,
   recovery_GLOBAL_STOP,
   recovery_COMPLETED
};

enum eRecoveryShadowDecision
{
   recovery_SHADOW_NONE = 0,
   recovery_SHADOW_WOULD_OPEN_HEDGE
};

input group "16 — Adaptive Recovery Hedge"
input eRecoveryMode RecoveryMode_          = recovery_OFF; // OFF / SHADOW / ACTIVE
input long          RecoveryMagic_         = 20260807;     // Separate from Core Magic
input int           RecoveryStartAfterDca_ = 5;            // Initial Core order is excluded
input double        HedgeGapPips_          = 50.0;         // Technical baseline: XAU 50 pips = 5.00 price

struct SRecoveryFoundationConfig
{
   eRecoveryMode mode;
   long          recoveryMagic;
   int           startAfterDca;
   double        hedgeGapPips;
};

void Recovery_LoadFoundationConfig(SRecoveryFoundationConfig &cfg)
{
   cfg.mode          = RecoveryMode_;
   cfg.recoveryMagic = RecoveryMagic_;
   cfg.startAfterDca = RecoveryStartAfterDca_;
   cfg.hedgeGapPips  = HedgeGapPips_;
}

bool Recovery_ModeValid(const eRecoveryMode mode)
{
   return mode == recovery_OFF || mode == recovery_SHADOW || mode == recovery_ACTIVE;
}

int Recovery_CycleKey(const eRecoveryCoreDirection dir)
{
   return dir == recovery_CORE_BUY ? 1 : 2;
}

string Recovery_DirectionName(const eRecoveryCoreDirection dir)
{
   return dir == recovery_CORE_BUY ? "BUY_CORE" : "SELL_CORE";
}

string Recovery_StateName(const eRecoveryState state)
{
   switch(state)
   {
      case recovery_CORE_ONLY:          return "CORE_ONLY";
      case recovery_ARMED:              return "ARMED";
      case recovery_HEDGE_BUILDING:     return "HEDGE_BUILDING";
      case recovery_HEDGE_ACTIVE:       return "HEDGE_ACTIVE";
      case recovery_HEDGE_TP_PENDING:   return "HEDGE_TP_PENDING";
      case recovery_CORE_CLOSE_PENDING: return "CORE_CLOSE_PENDING";
      case recovery_HEDGE_LOCK_PENDING: return "HEDGE_LOCK_PENDING";
      case recovery_HEDGE_LOCKED:       return "HEDGE_LOCKED";
      case recovery_REHEDGE_PENDING:    return "REHEDGE_PENDING";
      case recovery_PAUSE_SOFT:         return "PAUSE_SOFT";
      case recovery_PAUSE_HARD:         return "PAUSE_HARD";
      case recovery_RECONCILE_REQUIRED: return "RECONCILE_REQUIRED";
      case recovery_GLOBAL_STOP:        return "GLOBAL_STOP";
      case recovery_COMPLETED:          return "COMPLETED";
   }
   return "UNKNOWN";
}

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

   // Core Magic 0 is indistinguishable from manual magic-0 positions. Legacy
   // OFF behavior still permits it; Recovery requires an unambiguous owner.
   if(coreMagic <= 0)
   {
      why = "Core Magic must be > 0 when Recovery is enabled";
      return false;
   }
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

bool Recovery_ValidateShadowConfig(const eRecoveryMode mode,
                                   const double hedgeGapPips,
                                   string &why)
{
   why = "";
   if(mode == recovery_OFF) return true;
   if(hedgeGapPips < 0.0)
   {
      why = "HedgeGapPips_ must be >= 0";
      return false;
   }
   return true;
}

#endif // BD_RECOVERY_TYPES_MQH
