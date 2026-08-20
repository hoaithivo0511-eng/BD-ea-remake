//+------------------------------------------------------------------+
//| RecoveryT164Reachability.mqh — cross-field reachability guards   |
//| Pure policy only. No trade API calls.                            |
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_T164_REACHABILITY_MQH
#define BD_RECOVERY_T164_REACHABILITY_MQH

#include "RecoveryTypes.mqh"

// RecoveryStartAfterDca_=N means one initial Core + N DCA must currently be
// open because the approved T16 semantic is based on CURRENT open Core count.
int Recovery_T164RequiredCoreCountPure(const int startAfterDca)
{
   if(startAfterDca < 0) return -1;
   return startAfterDca + 1;
}

bool Recovery_T164SideReachablePure(const bool sideEnabled,
                                    const int maxOrders,
                                    const int startAfterDca)
{
   if(!sideEnabled) return true;
   int required = Recovery_T164RequiredCoreCountPure(startAfterDca);
   if(required < 1 || maxOrders < 1) return false;
   return required <= maxOrders;
}

bool Recovery_T164ValidateReachabilityPure(const eRecoveryMode mode,
                                           const bool buyEnabled,
                                           const bool sellEnabled,
                                           const int maxOrdersBuy,
                                           const int maxOrdersSell,
                                           const int startAfterDca)
{
   if(mode != recovery_ACTIVE) return true;
   return Recovery_T164SideReachablePure(buyEnabled, maxOrdersBuy, startAfterDca) &&
          Recovery_T164SideReachablePure(sellEnabled, maxOrdersSell, startAfterDca);
}

bool Recovery_T164ValidateReachability(const eRecoveryMode mode,
                                       const bool buyEnabled,
                                       const bool sellEnabled,
                                       const int maxOrdersBuy,
                                       const int maxOrdersSell,
                                       const int startAfterDca,
                                       string &why)
{
   why = "";
   if(mode != recovery_ACTIVE) return true;
   int required = Recovery_T164RequiredCoreCountPure(startAfterDca);
   if(required < 1)
   {
      why = "RecoveryStartAfterDca_ không hợp lệ";
      return false;
   }
   if(buyEnabled && !Recovery_T164SideReachablePure(true, maxOrdersBuy, startAfterDca))
   {
      why = "Recovery BUY không thể kích hoạt: cần " + (string)required +
            " lệnh Core đang mở (1 lệnh đầu + " + (string)startAfterDca +
            " DCA) nhưng MaxOrdersBuy=" + (string)maxOrdersBuy;
      return false;
   }
   if(sellEnabled && !Recovery_T164SideReachablePure(true, maxOrdersSell, startAfterDca))
   {
      why = "Recovery SELL không thể kích hoạt: cần " + (string)required +
            " lệnh Core đang mở (1 lệnh đầu + " + (string)startAfterDca +
            " DCA) nhưng MaxOrdersSell=" + (string)maxOrdersSell;
      return false;
   }
   return true;
}

// Overlap can legally trim the currently-open Core count before Recovery can
// reach its threshold when the Overlap count starts strictly earlier than the
// required Core count. This is a warning only; changing the trigger to a
// cumulative-DCA semantic requires a separate owner decision.
bool Recovery_T164OverlapMayPreemptPure(const bool overlapEnabled,
                                        const int overlapOrderNumber,
                                        const int startAfterDca)
{
   if(!overlapEnabled || overlapOrderNumber < 1 || startAfterDca < 0) return false;
   return overlapOrderNumber < Recovery_T164RequiredCoreCountPure(startAfterDca);
}

#endif // BD_RECOVERY_T164_REACHABILITY_MQH
