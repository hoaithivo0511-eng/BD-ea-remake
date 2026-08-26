//+------------------------------------------------------------------+
//| RecoveryT165MarginReserve.mqh — T17.6 DCA margin reserve         |
//| Conservative preflight: before a Core DCA that can participate   |
//| in Recovery, reserve enough current free margin for that DCA and |
//| the next LEGAL ARCS Hedge generation implied by post-DCA Core.   |
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_T165_MARGIN_RESERVE_MQH
#define BD_RECOVERY_T165_MARGIN_RESERVE_MQH

#include "RecoveryT165Policy.mqh"
#include "RecoveryArcsBook.mqh"
#include "RecoveryBundle.mqh"
#include <BlackDragon/GridEngine.mqh>

bool Recovery_T165ProjectedDcaReserveAllows(const int coreDir,
                                            const BasketSide &side,
                                            const double proposedCoreLot,
                                            const bool futureGenerationAllowed,
                                            string &why,
                                            double &requiredMarginOut,
                                            double &projectedHedgeLotOut)
{
   why = "";
   requiredMarginOut = 0.0;
   projectedHedgeLotOut = 0.0;
   if(RecoveryMode_ != recovery_ACTIVE || !RecoveryDcaMarginReserve_) return true;
   if(!futureGenerationAllowed) return true;
   if(coreDir != BD_DIR_BUY && coreDir != BD_DIR_SELL) return false;
   if(proposedCoreLot <= 0.0) return true;

   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0)
   {
      why = "T16.5 margin reserve: broker volume step unavailable";
      return false;
   }

   eRecoveryCoreDirection rdir = coreDir == BD_DIR_BUY ?
                                  recovery_CORE_BUY : recovery_CORE_SELL;
   // T17.6: threshold reachability is exact Core Magic as well. Managed
   // manual magic-0 positions must not make the Recovery trigger appear closer.
   SArcsPosition exactTriggerCore[];
   int currentCoreCount = Recovery_ArcsBuildCore(rdir, step, exactTriggerCore);
   if(currentCoreCount <= 0) return true;
   int postCount = currentCoreCount + 1;
   if(!Recovery_DcaThresholdReached(postCount, RecoveryStartAfterDca_))
      return true;

   double normalizedCoreLot = Grid_NormalizeVolume(proposedCoreLot);
   if(normalizedCoreLot <= 0.0)
   {
      why = "T16.5 margin reserve: proposed Core DCA volume invalid";
      return false;
   }

   // T17.6: projected Core exposure uses exact Core Magic, never an aggregate
   // BasketSide that may include flag_Hand_Ord magic-0 positions.
   long currentCoreUnits = Recovery_ArcsCoreUnits(rdir, step);
   long dcaUnits = Recovery_VolumeToUnitsFloor(normalizedCoreLot, step);
   long postCoreUnits = currentCoreUnits + dcaUnits;
   long existingHedgeUnits = Recovery_ArcsTotalHedgeUnits(rdir, step);
   long targetHedgeUnits = Recovery_T16NewGenerationUnitsPure(RecoverySizingPolicy_,
                                                              postCoreUnits,
                                                              existingHedgeUnits,
                                                              HedgeVolumePercent_);
   if(targetHedgeUnits <= 0) return true;

   SRecoveryBundleVolumeMeta meta;
   if(!Recovery_ReadBundleVolumeMeta(_Symbol, meta, why))
   {
      why = "T16.5 margin reserve: " + why;
      return false;
   }

   int hedgeDir = Recovery_HedgeDirection(rdir);
   long directional = Recovery_DirectionalExposureUnits(_Symbol, hedgeDir,
                                                        meta.volumeStep);
   long children[];
   if(!Recovery_BuildBundlePlan(targetHedgeUnits,
                                meta.minUnits,
                                meta.maxOrderUnits,
                                directional,
                                meta.volumeLimitUnits,
                                children, why))
   {
      why = "T16.5 margin reserve: projected Hedge bundle blocked: " + why;
      return false;
   }

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick) || tick.bid <= 0.0 || tick.ask <= 0.0)
   {
      why = "T16.5 margin reserve: no fresh tick";
      return false;
   }

   double dcaMargin = 0.0;
   ENUM_ORDER_TYPE coreType = coreDir == BD_DIR_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double corePrice = coreDir == BD_DIR_BUY ? tick.ask : tick.bid;
   if(!OrderCalcMargin(coreType, _Symbol, normalizedCoreLot, corePrice, dcaMargin))
   {
      why = "T16.5 margin reserve: OrderCalcMargin Core failed error=" + (string)GetLastError();
      return false;
   }

   double hedgeMargin = 0.0;
   ENUM_ORDER_TYPE hedgeType = hedgeDir == 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double hedgePrice = hedgeDir == 0 ? tick.ask : tick.bid;
   for(int i = 0; i < ArraySize(children); i++)
   {
      double childLot = Recovery_UnitsToVolume(children[i], meta.volumeStep);
      double childMargin = 0.0;
      if(!OrderCalcMargin(hedgeType, _Symbol, childLot, hedgePrice, childMargin))
      {
         why = "T16.5 margin reserve: OrderCalcMargin Hedge child failed error=" + (string)GetLastError();
         return false;
      }
      if(childMargin < 0.0)
      {
         why = "T16.5 margin reserve: negative Hedge margin estimate";
         return false;
      }
      hedgeMargin += childMargin;
   }

   if(dcaMargin < 0.0)
   {
      why = "T16.5 margin reserve: negative Core margin estimate";
      return false;
   }

   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   requiredMarginOut = dcaMargin + hedgeMargin;
   projectedHedgeLotOut = Recovery_UnitsToVolume(targetHedgeUnits, meta.volumeStep);
   if(!Recovery_T165MarginReserveAllowsPure(freeMargin, dcaMargin, hedgeMargin))
   {
      why = "T16.5 DCA blocked by margin reserve: free=" + DoubleToString(freeMargin, 2) +
            " required(DCA+nextHedge)=" + DoubleToString(requiredMarginOut, 2) +
            " nextCore=" + DoubleToString(normalizedCoreLot, 2) +
            " projectedHedge=" + DoubleToString(projectedHedgeLotOut, 2);
      return false;
   }
   return true;
}

#endif // BD_RECOVERY_T165_MARGIN_RESERVE_MQH
