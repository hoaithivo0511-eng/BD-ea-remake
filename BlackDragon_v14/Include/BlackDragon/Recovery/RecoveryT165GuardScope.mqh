//+------------------------------------------------------------------+
//| RecoveryT165GuardScope.mqh — T16.5 Guard scope coherence         |
//| Floating Recovery exposure is read live. Realized-day Recovery   |
//| cash is SEEDED once/day and maintained from Recovery deal events,|
//| avoiding HistorySelect/full-history scans on every tick.         |
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_T165_GUARD_SCOPE_MQH
#define BD_RECOVERY_T165_GUARD_SCOPE_MQH

#include "RecoveryT165Policy.mqh"
#include <BlackDragon/CashLedger.mqh>

struct SRecoveryT165GuardMetrics
{
   double recoveryForBuyFloating;
   double recoveryForSellFloating;
   double recoveryRealizedToday;
   bool   buyRecoveryOpen;
   bool   sellRecoveryOpen;
   bool   historyOk;
};

CScopedDayCashLedger g_t1724RecoveryDayCash;

void Recovery_T165GuardMetricsReset(SRecoveryT165GuardMetrics &m)
{
   ZeroMemory(m); m.historyOk=true;
}
bool Recovery_T165SeedRealizedCache(const datetime now)
{
   g_t1724RecoveryDayCash.Configure(_Symbol,(long)RecoveryMagic_,false);
   g_t1724RecoveryDayCash.Invalidate();
   return g_t1724RecoveryDayCash.Refresh(now);
}
void Recovery_T165InvalidateGuardCash()
{ g_t1724RecoveryDayCash.Invalidate(); }
void Recovery_T165GuardObserveDeal(const ulong deal,const datetime now)
{
   if(RecoveryMode_!=recovery_ACTIVE || RecoveryMagic_<=0 || deal==0) return;
   g_t1724RecoveryDayCash.Configure(_Symbol,(long)RecoveryMagic_,false);
   g_t1724RecoveryDayCash.Observe(deal,now);
}

void Recovery_T165ReadRecoveryFloating(const string symbol,
                                       const long recoveryMagic,
                                       SRecoveryT165GuardMetrics &m)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != symbol ||
         PositionGetInteger(POSITION_MAGIC) != recoveryMagic)
         continue;

      long type = PositionGetInteger(POSITION_TYPE);
      double cash = PositionGetDouble(POSITION_PROFIT) +
                    PositionGetDouble(POSITION_SWAP);
      if(type == POSITION_TYPE_SELL)
      {
         m.recoveryForBuyFloating += cash;
         m.buyRecoveryOpen = true;
      }
      else if(type == POSITION_TYPE_BUY)
      {
         m.recoveryForSellFloating += cash;
         m.sellRecoveryOpen = true;
      }
   }
}

bool Recovery_T165ReadGuardMetrics(const datetime now,
                                   SRecoveryT165GuardMetrics &m)
{
   Recovery_T165GuardMetricsReset(m);
   if(RecoveryMode_ != recovery_ACTIVE || RecoveryMagic_ <= 0)
      return true;

   Recovery_T165ReadRecoveryFloating(_Symbol, (long)RecoveryMagic_, m);
   g_t1724RecoveryDayCash.Configure(_Symbol,(long)RecoveryMagic_,false);
   m.historyOk=g_t1724RecoveryDayCash.Refresh(now);
   if(m.historyOk) m.recoveryRealizedToday=g_t1724RecoveryDayCash.Cash();
   return m.historyOk;
}

#endif // BD_RECOVERY_T165_GUARD_SCOPE_MQH
