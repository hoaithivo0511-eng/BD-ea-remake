//+------------------------------------------------------------------+
//| OverlapT177Policy.mqh — T17.7 C3 durable two-leg policy         |
//| Pure lifecycle/economics helpers; no trade or file API calls.    |
//+------------------------------------------------------------------+
#ifndef BD_OVERLAP_T177_POLICY_MQH
#define BD_OVERLAP_T177_POLICY_MQH

#include <BlackDragon/ExitEngine.mqh>

enum eOverlapT177State
{
   overlap_T177_IDLE = 0,
   overlap_T177_PAIR_ARMED,
   overlap_T177_LEG1_SUBMITTED,
   overlap_T177_LEG1_CONFIRMED,
   overlap_T177_LEG2_RECHECK,
   overlap_T177_LEG2_WAIT_SAFE,
   overlap_T177_LEG2_SUBMITTED,
   overlap_T177_COMPLETE,
   overlap_T177_RECONCILE
};

enum eOverlapT177DriveDisposition
{
   overlap_T177_DRIVE_NO_EFFECT = 0,
   overlap_T177_DRIVE_WAIT,
   overlap_T177_DRIVE_MUTATED,
   overlap_T177_DRIVE_PENDING,
   overlap_T177_DRIVE_RECONCILE
};

enum eOverlapT177SubmitObservation
{
   overlap_T177_OBS_PENDING = 0,
   overlap_T177_OBS_CONFIRMED,
   overlap_T177_OBS_REJECTED,
   overlap_T177_OBS_RECONCILE
};

enum eOverlapT177Route
{
   overlap_T177_ROUTE_NONE = 0,
   overlap_T177_ROUTE_DIRECT,
   overlap_T177_ROUTE_RECOVERY
};

bool Overlap_T177StateValidPure(const int rawState)
{
   return rawState >= (int)overlap_T177_IDLE &&
          rawState <= (int)overlap_T177_RECONCILE;
}

bool Overlap_T177PreLeg1EligiblePure(const int sideCount,
                                     const int overlapFromOrder,
                                     const bool overlapOn,
                                     const double firstProfit,
                                     const double lastProfit,
                                     const double overlapPercent,
                                     const double executionReserveCash)
{
   if(!Exit_OverlapHit(sideCount, overlapFromOrder, overlapOn,
                       firstProfit, lastProfit, overlapPercent))
      return false;
   return Exit_OverlapExecutionSafePure(firstProfit, lastProfit,
                                        executionReserveCash);
}

// After leg 1 is broker-confirmed, only ACTUAL realized leg-1 cash may fund
// the still-live losing leg. The leg-2 close is allowed only when that realized
// cash plus CURRENT leg-2 floating covers the CURRENT one-request execution
// reserve. This reuses the T17.5 reserve contract instead of inventing a new
// cost formula.
bool Overlap_T177Leg2SafePure(const double leg1RealizedCash,
                              const double leg2FloatingCash,
                              const double leg2ExecutionReserveCash)
{
   if(leg2ExecutionReserveCash == DBL_MAX) return false;
   return leg1RealizedCash + leg2FloatingCash + 1e-9 >=
          MathMax(leg2ExecutionReserveCash, 0.0);
}

eOverlapT177SubmitObservation Overlap_T177SubmittedObservationPure(
   const bool loadedFromDisk,
   const bool ticketLive,
   const bool pending,
   const bool reconcileRequired)
{
   if(reconcileRequired) return overlap_T177_OBS_RECONCILE;
   if(pending) return overlap_T177_OBS_PENDING;
   if(!ticketLive) return overlap_T177_OBS_CONFIRMED;
   // A submitted state restored after restart has lost its in-memory execution
   // journal/coordinator identity. A still-live ticket is therefore ambiguous.
   if(loadedFromDisk) return overlap_T177_OBS_RECONCILE;
   // Same-session live + no pending journal means the request has a proven
   // non-execution/rejection outcome. It may be re-armed on a later tick after
   // fresh economics, but never blindly retried as the same request.
   return overlap_T177_OBS_REJECTED;
}

bool Overlap_T177ConsumesStrategyTickPure(const eOverlapT177DriveDisposition d)
{
   return d == overlap_T177_DRIVE_MUTATED ||
          d == overlap_T177_DRIVE_PENDING ||
          d == overlap_T177_DRIVE_RECONCILE;
}

bool Overlap_T177AllowsOtherModulesPure(const eOverlapT177DriveDisposition d)
{
   return d == overlap_T177_DRIVE_NO_EFFECT ||
          d == overlap_T177_DRIVE_WAIT;
}

bool Overlap_T177BlocksSidePure(const eOverlapT177State state)
{
   return state != overlap_T177_IDLE && state != overlap_T177_COMPLETE;
}

bool Overlap_T177SubmittedStatePure(const eOverlapT177State state)
{
   return state == overlap_T177_LEG1_SUBMITTED ||
          state == overlap_T177_LEG2_SUBMITTED;
}

string Overlap_T177StateNameVi(const eOverlapT177State state)
{
   switch(state)
   {
      case overlap_T177_IDLE:            return "RẢNH";
      case overlap_T177_PAIR_ARMED:      return "ĐÃ KHÓA CẶP";
      case overlap_T177_LEG1_SUBMITTED:  return "ĐANG ĐÓNG LỆNH 1";
      case overlap_T177_LEG1_CONFIRMED:  return "LỆNH 1 ĐÃ ĐÓNG";
      case overlap_T177_LEG2_RECHECK:    return "KIỂM TRA LỆNH 2";
      case overlap_T177_LEG2_WAIT_SAFE:  return "CHỜ LỆNH 2 AN TOÀN";
      case overlap_T177_LEG2_SUBMITTED:  return "ĐANG ĐÓNG LỆNH 2";
      case overlap_T177_COMPLETE:        return "HOÀN TẤT";
      case overlap_T177_RECONCILE:       return "LỖI / ĐỐI SOÁT";
   }
   return "KHÔNG RÕ";
}

#endif // BD_OVERLAP_T177_POLICY_MQH
