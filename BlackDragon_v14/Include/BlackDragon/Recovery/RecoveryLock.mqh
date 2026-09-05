//+------------------------------------------------------------------+
//| RecoveryLock.mqh — T6 hedge lock + re-hedge mechanics           |
//| Invariants: no direct OrderSend; deterministic price/gap rules.  |
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_LOCK_MQH
#define BD_RECOVERY_LOCK_MQH

#include "RecoveryExit.mqh"

struct SRecoveryLockTicket
{
   ulong  ticket;
   long   type;
   long   units;
   double lots;
   double openPrice;
   double sl;
   double tp;
};

struct SRecoveryLockSnapshot
{
   long   activeUnits;
   double activeLots;
   double weightedEntry;
   double netBE;
   int    ticketCount;
};

double Recovery_NormalizeLockPricePure(const eRecoveryCoreDirection dir,
                                       const double price,
                                       const double tickSize,
                                       const int digits)
{
   if(price <= 0.0 || tickSize <= 0.0) return 0.0;
   double q = price / tickSize;
   // BUY Core => SELL hedge: lower SL locks more profit, so floor.
   // SELL Core => BUY hedge: higher SL locks more profit, so ceil.
   double ticks = dir == recovery_CORE_BUY ? MathFloor(q + 1e-9)
                                           : MathCeil(q - 1e-9);
   return NormalizeDouble(ticks * tickSize, digits);
}

double Recovery_LockTargetPricePure(const eRecoveryCoreDirection dir,
                                    const double weightedEntry,
                                    const double hedgeNetBE,
                                    const double configuredProfitDistance,
                                    const double safetyBufferDistance,
                                    const double tickSize,
                                    const int digits)
{
   if(weightedEntry <= 0.0 || hedgeNetBE <= 0.0 ||
      configuredProfitDistance < 0.0 || safetyBufferDistance <= 0.0 ||
      tickSize <= 0.0)
      return 0.0;

   double raw = 0.0;
   if(dir == recovery_CORE_BUY)
      raw = MathMin(weightedEntry - configuredProfitDistance,
                    hedgeNetBE - safetyBufferDistance);
   else
      raw = MathMax(weightedEntry + configuredProfitDistance,
                    hedgeNetBE + safetyBufferDistance);

   double target = Recovery_NormalizeLockPricePure(dir, raw, tickSize, digits);
   double eps = tickSize * 0.5;
   if(dir == recovery_CORE_BUY)
   {
      if(target >= hedgeNetBE - eps) return 0.0;
   }
   else
   {
      if(target <= hedgeNetBE + eps) return 0.0;
   }
   return target;
}

bool Recovery_LockSatisfiedPure(const eRecoveryCoreDirection dir,
                                const double observedSl,
                                const double targetSl,
                                const double tickSize)
{
   if(observedSl <= 0.0 || targetSl <= 0.0) return false;
   double eps = tickSize > 0.0 ? tickSize * 0.5 : 1e-9;
   if(dir == recovery_CORE_BUY)
      return observedSl <= targetSl + eps; // SELL hedge: lower is stronger
   return observedSl >= targetSl - eps;    // BUY hedge: higher is stronger
}

bool Recovery_LockBrokerDistanceValidPure(const eRecoveryCoreDirection dir,
                                          const double targetSl,
                                          const double bid,
                                          const double ask,
                                          const double point,
                                          const int stopsLevelPoints,
                                          const int freezeLevelPoints,
                                          const double tickSize)
{
   if(targetSl <= 0.0 || bid <= 0.0 || ask <= 0.0 ||
      point <= 0.0 || tickSize <= 0.0)
      return false;
   int stops = stopsLevelPoints < 0 ? 0 : stopsLevelPoints;
   int freeze = freezeLevelPoints < 0 ? 0 : freezeLevelPoints;
   int requiredPoints = MathMax(stops, freeze);
   double distance = (double)requiredPoints * point;
   double eps = tickSize * 0.5;

   // BUY Core => SELL hedge, SL must stay above current Ask.
   if(dir == recovery_CORE_BUY)
      return targetSl + eps >= ask + distance;

   // SELL Core => BUY hedge, SL must stay below current Bid.
   return targetSl - eps <= bid - distance;
}

bool Recovery_GenerationCanStartPure(const int currentGeneration,
                                     const int maxGenerations)
{
   return currentGeneration >= 0 && maxGenerations >= 1 &&
          currentGeneration < maxGenerations;
}

bool Recovery_RehedgeGapHitPure(const eRecoveryCoreDirection dir,
                                const long anchorTicks,
                                const long bidTicks,
                                const long askTicks,
                                const long gapTicks)
{
   return Recovery_AdverseGapHitTicks(dir, anchorTicks, bidTicks, askTicks, gapTicks);
}

long Recovery_WeightedAnchorTicksPure(const double weightedPriceUnits,
                                      const long units,
                                      const double tickSize)
{
   if(weightedPriceUnits <= 0.0 || units <= 0 || tickSize <= 0.0) return 0;
   double avg = weightedPriceUnits / (double)units;
   return Recovery_PriceToTicksPure(avg, tickSize);
}

double Recovery_LockPositionEntryCosts(const string symbol,
                                       const long recoveryMagic,
                                       const ulong positionIdentifier)
{
   if(positionIdentifier == 0 || !HistorySelectByPosition(positionIdentifier)) return 0.0;
   double costs = 0.0;
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0) continue;
      if(HistoryDealGetString(deal, DEAL_SYMBOL) != symbol ||
         HistoryDealGetInteger(deal, DEAL_MAGIC) != recoveryMagic)
         continue;
      long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_IN && entry != DEAL_ENTRY_INOUT) continue;
      costs += HistoryDealGetDouble(deal, DEAL_COMMISSION)
             + HistoryDealGetDouble(deal, DEAL_FEE);
   }
   return costs;
}

void Recovery_SortLockTickets(SRecoveryLockTicket &items[])
{
   for(int i = 1; i < ArraySize(items); i++)
   {
      SRecoveryLockTicket key = items[i];
      int j = i - 1;
      while(j >= 0 && items[j].ticket > key.ticket)
      {
         items[j + 1] = items[j];
         j--;
      }
      items[j + 1] = key;
   }
}

bool Recovery_BuildLockSnapshot(const string symbol,
                                const long recoveryMagic,
                                const eRecoveryCoreDirection dir,
                                const double volumeStep,
                                const double tickSize,
                                SRecoveryLockTicket &tickets[],
                                SRecoveryLockSnapshot &snapshot,
                                string &why)
{
   ArrayResize(tickets, 0);
   snapshot.activeUnits = 0;
   snapshot.activeLots = 0.0;
   snapshot.weightedEntry = 0.0;
   snapshot.netBE = 0.0;
   snapshot.ticketCount = 0;
   why = "";
   if(symbol == "" || recoveryMagic <= 0 || volumeStep <= 0.0 || tickSize <= 0.0)
   {
      why = "invalid T6 lock snapshot metadata";
      return false;
   }

   long wantedType = Recovery_HedgeDirection(dir) == 0 ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   double weighted = 0.0;
   double signedCosts = 0.0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != symbol ||
         PositionGetInteger(POSITION_MAGIC) != recoveryMagic ||
         PositionGetInteger(POSITION_TYPE) != wantedType)
         continue;

      double lots = PositionGetDouble(POSITION_VOLUME);
      long units = Recovery_VolumeToUnitsFloor(lots, volumeStep);
      if(units <= 0 || lots <= 0.0) continue;

      SRecoveryLockTicket t;
      t.ticket = ticket;
      t.type = wantedType;
      t.units = units;
      t.lots = lots;
      t.openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      t.sl = PositionGetDouble(POSITION_SL);
      t.tp = PositionGetDouble(POSITION_TP);
      int n = ArraySize(tickets);
      ArrayResize(tickets, n + 1);
      tickets[n] = t;

      snapshot.activeUnits += units;
      snapshot.activeLots += lots;
      weighted += t.openPrice * lots;
      signedCosts += PositionGetDouble(POSITION_SWAP);
      ulong identifier = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
      signedCosts += Recovery_LockPositionEntryCosts(symbol, recoveryMagic, identifier);
   }

   if(snapshot.activeUnits <= 0 || snapshot.activeLots <= 0.0)
   {
      why = "no active Recovery hedge remains to lock";
      return false;
   }

   double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickValue <= 0.0)
   {
      why = "SYMBOL_TRADE_TICK_VALUE unavailable for net-positive lock";
      return false;
   }

   snapshot.weightedEntry = weighted / snapshot.activeLots;
   bool hedgeIsBuy = wantedType == POSITION_TYPE_BUY;
   snapshot.netBE = Recovery_NetBreakevenFromCosts(snapshot.weightedEntry,
                                                    snapshot.activeLots,
                                                    signedCosts,
                                                    tickValue,
                                                    tickSize,
                                                    hedgeIsBuy);
   if(snapshot.netBE <= 0.0)
   {
      why = "unable to calculate Recovery hedge net breakeven";
      return false;
   }
   Recovery_SortLockTickets(tickets);
   snapshot.ticketCount = ArraySize(tickets);
   return snapshot.ticketCount > 0;
}

int Recovery_FindWeakLockTicket(const eRecoveryCoreDirection dir,
                                SRecoveryLockTicket &tickets[],
                                const double targetSl,
                                const double tickSize)
{
   for(int i = 0; i < ArraySize(tickets); i++)
      if(!Recovery_LockSatisfiedPure(dir, tickets[i].sl, targetSl, tickSize))
         return i;
   return -1;
}

long Recovery_CurrentCoreUnits(const string symbol,
                               const long coreMagic,
                               const eRecoveryCoreDirection dir,
                               const double volumeStep)
{
   if(symbol == "" || volumeStep <= 0.0) return 0;
   long wanted = dir == recovery_CORE_BUY ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   long units = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != symbol ||
         PositionGetInteger(POSITION_MAGIC) != coreMagic ||
         PositionGetInteger(POSITION_TYPE) != wanted)
         continue;
      units += Recovery_VolumeToUnitsFloor(PositionGetDouble(POSITION_VOLUME), volumeStep);
   }
   return units;
}

#endif // BD_RECOVERY_LOCK_MQH
