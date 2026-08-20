//+------------------------------------------------------------------+
//| RecoveryBundle.mqh — T4 logical HedgeBundle smart-split rules    |
//| Purpose   : Exact integer-unit split/preflight/lifecycle helpers.|
//| Invariants: Never round aggregate hedge above requested target.  |
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_BUNDLE_MQH
#define BD_RECOVERY_BUNDLE_MQH

#include "RecoveryStateMachine.mqh"

struct SRecoveryBundleVolumeMeta
{
   double volumeStep;
   long   minUnits;
   long   maxOrderUnits;
   long   volumeLimitUnits; // 0 => broker reports no aggregate directional limit
};

bool Recovery_ReadBundleVolumeMeta(const string symbol,
                                   SRecoveryBundleVolumeMeta &meta,
                                   string &why)
{
   why = "";
   meta.volumeStep       = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   double volumeMin      = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double volumeMax      = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double volumeLimit    = SymbolInfoDouble(symbol, SYMBOL_VOLUME_LIMIT);

   if(meta.volumeStep <= 0.0 || volumeMin <= 0.0 || volumeMax <= 0.0)
   {
      why = "invalid broker volume step/min/max metadata";
      return false;
   }

   meta.minUnits        = Recovery_VolumeToUnitsCeil(volumeMin, meta.volumeStep);
   meta.maxOrderUnits   = Recovery_VolumeToUnitsFloor(volumeMax, meta.volumeStep);
   meta.volumeLimitUnits = volumeLimit > 0.0 ?
                           Recovery_VolumeToUnitsFloor(volumeLimit, meta.volumeStep) : 0;

   if(meta.minUnits <= 0 || meta.maxOrderUnits < meta.minUnits)
   {
      why = "broker volume min/max cannot be represented on volume step";
      return false;
   }
   return true;
}

bool Recovery_OrderIsBuyDirection(const long type)
{
   return type == ORDER_TYPE_BUY ||
          type == ORDER_TYPE_BUY_LIMIT ||
          type == ORDER_TYPE_BUY_STOP ||
          type == ORDER_TYPE_BUY_STOP_LIMIT;
}

bool Recovery_OrderIsSellDirection(const long type)
{
   return type == ORDER_TYPE_SELL ||
          type == ORDER_TYPE_SELL_LIMIT ||
          type == ORDER_TYPE_SELL_STOP ||
          type == ORDER_TYPE_SELL_STOP_LIMIT;
}

// SYMBOL_VOLUME_LIMIT is an aggregate per-symbol/per-direction broker rule,
// therefore ALL magics are counted here, not only Core/Recovery ownership.
long Recovery_DirectionalExposureUnits(const string symbol,
                                       const int direction, // 0 BUY, 1 SELL
                                       const double volumeStep)
{
   if(volumeStep <= 0.0) return 0;
   long totalUnits = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || PositionGetString(POSITION_SYMBOL) != symbol) continue;
      long type = PositionGetInteger(POSITION_TYPE);
      if((direction == 0 && type != POSITION_TYPE_BUY) ||
         (direction == 1 && type != POSITION_TYPE_SELL))
         continue;
      totalUnits += Recovery_VolumeToUnitsFloor(PositionGetDouble(POSITION_VOLUME), volumeStep);
   }

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || OrderGetString(ORDER_SYMBOL) != symbol) continue;
      long type = OrderGetInteger(ORDER_TYPE);
      bool sameDir = direction == 0 ? Recovery_OrderIsBuyDirection(type) :
                                      Recovery_OrderIsSellDirection(type);
      if(!sameDir) continue;
      totalUnits += Recovery_VolumeToUnitsFloor(OrderGetDouble(ORDER_VOLUME_CURRENT), volumeStep);
   }
   return totalUnits;
}

bool Recovery_VolumeLimitAllows(const long targetNewUnits,
                                const long existingDirectionalUnits,
                                const long volumeLimitUnits)
{
   if(targetNewUnits <= 0 || existingDirectionalUnits < 0 || volumeLimitUnits < 0)
      return false;
   if(volumeLimitUnits == 0) return true;
   if(existingDirectionalUnits > volumeLimitUnits) return false;
   return targetNewUnits <= volumeLimitUnits - existingDirectionalUnits;
}

// Return one exact child size for the current remaining target. If taking the
// max child would leave a residual below broker minimum, shrink this child so
// the residual becomes exactly the minimum. A return of 0 means the remaining
// target cannot be represented without under/over-hedging.
long Recovery_BundleNextChildUnits(const long remainingUnits,
                                   const long minUnits,
                                   const long maxOrderUnits)
{
   if(remainingUnits <= 0 || minUnits <= 0 || maxOrderUnits < minUnits)
      return 0;
   if(remainingUnits < minUnits) return 0;
   if(remainingUnits <= maxOrderUnits) return remainingUnits;

   long child = maxOrderUnits;
   long residual = remainingUnits - child;
   if(residual > 0 && residual < minUnits)
   {
      long shift = minUnits - residual;
      child -= shift;
      if(child < minUnits) return 0;
      residual = remainingUnits - child;
   }
   if(child < minUnits || child > maxOrderUnits) return 0;
   if(residual > 0 && residual < minUnits) return 0;
   return child;
}

bool Recovery_BuildBundlePlan(const long targetNewUnits,
                              const long minUnits,
                              const long maxOrderUnits,
                              const long existingDirectionalUnits,
                              const long volumeLimitUnits,
                              long &children[],
                              string &why)
{
   ArrayResize(children, 0);
   why = "";

   if(targetNewUnits <= 0)
   {
      why = "bundle target units must be > 0";
      return false;
   }
   if(minUnits <= 0 || maxOrderUnits < minUnits)
   {
      why = "invalid min/max order units";
      return false;
   }
   if(!Recovery_VolumeLimitAllows(targetNewUnits, existingDirectionalUnits, volumeLimitUnits))
   {
      why = "bundle would exceed SYMBOL_VOLUME_LIMIT in hedge direction";
      return false;
   }

   long remaining = targetNewUnits;
   while(remaining > 0)
   {
      long child = Recovery_BundleNextChildUnits(remaining, minUnits, maxOrderUnits);
      if(child <= 0)
      {
         ArrayResize(children, 0);
         why = "exact target cannot be split within broker min/max constraints";
         return false;
      }
      int n = ArraySize(children);
      ArrayResize(children, n + 1);
      children[n] = child;
      remaining -= child;
   }

   long sum = 0;
   for(int i = 0; i < ArraySize(children); i++)
   {
      if(children[i] < minUnits || children[i] > maxOrderUnits)
      {
         ArrayResize(children, 0);
         why = "internal child plan violated min/max constraint";
         return false;
      }
      sum += children[i];
   }
   if(sum != targetNewUnits)
   {
      ArrayResize(children, 0);
      why = "internal child plan did not preserve exact target units";
      return false;
   }
   return true;
}

long Recovery_RehedgeRequiredUnits(const long currentCoreUnits,
                                   const long activeRecoveryHedgeUnits)
{
   if(currentCoreUnits <= 0) return 0;
   if(activeRecoveryHedgeUnits <= 0) return currentCoreUnits;
   return currentCoreUnits > activeRecoveryHedgeUnits ?
          currentCoreUnits - activeRecoveryHedgeUnits : 0;
}

long Recovery_BundleConfirmedNewUnits(const long currentActiveHedgeUnits,
                                      const long baselineActiveHedgeUnits)
{
   if(currentActiveHedgeUnits <= baselineActiveHedgeUnits) return 0;
   return currentActiveHedgeUnits - baselineActiveHedgeUnits;
}

double Recovery_BundleCoveragePercent(const long confirmedNewUnits,
                                      const long targetNewUnits)
{
   if(confirmedNewUnits <= 0 || targetNewUnits <= 0) return 0.0;
   return (double)confirmedNewUnits / (double)targetNewUnits * 100.0;
}

bool Recovery_BundleCanSubmitNext(const long confirmedNewUnits,
                                  const long targetNewUnits,
                                  const bool childInFlight,
                                  const bool reconcileRequired,
                                  const bool blockedAfterReject)
{
   if(targetNewUnits <= 0 || confirmedNewUnits < 0) return false;
   if(confirmedNewUnits >= targetNewUnits) return false;
   if(childInFlight || reconcileRequired || blockedAfterReject) return false;
   return true;
}

// Conservative preflight only. OrderCalcMargin intentionally does not prove a
// future broker fill; the actual send/reconcile path remains authoritative.
bool Recovery_ChildMarginPreflight(const string symbol,
                                   const int direction, // 0 BUY, 1 SELL
                                   const long childUnits,
                                   const double volumeStep,
                                   string &why)
{
   why = "";
   if(childUnits <= 0 || volumeStep <= 0.0)
   {
      why = "invalid child volume";
      return false;
   }

   MqlTick tick;
   if(!SymbolInfoTick(symbol, tick))
   {
      why = "no current symbol tick for margin preflight";
      return false;
   }

   double volume = Recovery_UnitsToVolume(childUnits, volumeStep);
   ENUM_ORDER_TYPE orderType = direction == 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double price = direction == 0 ? tick.ask : tick.bid;
   double requiredMargin = 0.0;
   ResetLastError();
   if(!OrderCalcMargin(orderType, symbol, volume, price, requiredMargin))
   {
      why = "OrderCalcMargin failed error=" + (string)GetLastError();
      return false;
   }

   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(requiredMargin < 0.0 || freeMargin < requiredMargin)
   {
      why = "insufficient free margin for conservative child preflight";
      return false;
   }
   return true;
}

#endif // BD_RECOVERY_BUNDLE_MQH
