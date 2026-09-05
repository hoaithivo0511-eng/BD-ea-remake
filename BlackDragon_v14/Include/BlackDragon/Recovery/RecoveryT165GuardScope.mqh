//+------------------------------------------------------------------+
//| RecoveryT165GuardScope.mqh — T16.5 Guard scope coherence         |
//| Floating Recovery exposure is read live. Realized-day Recovery   |
//| cash is SEEDED once/day and maintained from Recovery deal events,|
//| avoiding HistorySelect/full-history scans on every tick.         |
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_T165_GUARD_SCOPE_MQH
#define BD_RECOVERY_T165_GUARD_SCOPE_MQH

#include "RecoveryT165Policy.mqh"

struct SRecoveryT165GuardMetrics
{
   double recoveryForBuyFloating;
   double recoveryForSellFloating;
   double recoveryRealizedToday;
   bool   buyRecoveryOpen;
   bool   sellRecoveryOpen;
   bool   historyOk;
};

datetime g_t165GuardDayStart = 0;
double   g_t165GuardRealized = 0.0;
bool     g_t165GuardSeeded   = false;
ulong    g_t165GuardSeenDeals[];

void Recovery_T165GuardMetricsReset(SRecoveryT165GuardMetrics &m)
{
   m.recoveryForBuyFloating  = 0.0;
   m.recoveryForSellFloating = 0.0;
   m.recoveryRealizedToday   = 0.0;
   m.buyRecoveryOpen         = false;
   m.sellRecoveryOpen        = false;
   m.historyOk               = true;
}

bool Recovery_T165GuardDealSeen(const ulong deal)
{
   if(deal == 0) return true;
   for(int i = 0; i < ArraySize(g_t165GuardSeenDeals); i++)
      if(g_t165GuardSeenDeals[i] == deal) return true;
   return false;
}

void Recovery_T165GuardRememberDeal(const ulong deal)
{
   if(deal == 0 || Recovery_T165GuardDealSeen(deal)) return;
   int n = ArraySize(g_t165GuardSeenDeals);
   ArrayResize(g_t165GuardSeenDeals, n + 1);
   g_t165GuardSeenDeals[n] = deal;
}

double Recovery_T165DealCash(const ulong deal)
{
   return HistoryDealGetDouble(deal, DEAL_PROFIT)
        + HistoryDealGetDouble(deal, DEAL_SWAP)
        + HistoryDealGetDouble(deal, DEAL_COMMISSION)
        + HistoryDealGetDouble(deal, DEAL_FEE);
}

bool Recovery_T165SeedRealizedCache(const datetime now)
{
   datetime dayStart = StringToTime(TimeToString(now, TIME_DATE));
   g_t165GuardDayStart = dayStart;
   g_t165GuardRealized = 0.0;
   g_t165GuardSeeded = false;
   ArrayResize(g_t165GuardSeenDeals, 0);

   if(RecoveryMode_ != recovery_ACTIVE || RecoveryMagic_ <= 0)
   {
      g_t165GuardSeeded = true;
      return true;
   }
   if(!HistorySelect(dayStart, now + 1)) return false;

   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0) continue;
      if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol ||
         HistoryDealGetInteger(deal, DEAL_MAGIC) != (long)RecoveryMagic_)
         continue;
      long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY) continue;
      g_t165GuardRealized += Recovery_T165DealCash(deal);
      Recovery_T165GuardRememberDeal(deal);
   }
   g_t165GuardSeeded = true;
   return true;
}

// Idempotent observer for every broker-confirmed deal received by Recovery.
// The engine calls this AFTER its own ledger/identity handling so HistorySelect
// here cannot disturb the active Recovery transaction path.
void Recovery_T165GuardObserveDeal(const ulong deal, const datetime now)
{
   if(RecoveryMode_ != recovery_ACTIVE || RecoveryMagic_ <= 0 || deal == 0) return;
   datetime dayStart = StringToTime(TimeToString(now, TIME_DATE));
   if(!g_t165GuardSeeded || g_t165GuardDayStart != dayStart)
   {
      Recovery_T165SeedRealizedCache(now); // already includes this DEAL_ADD
      return;
   }
   if(Recovery_T165GuardDealSeen(deal)) return;
   if(!HistoryDealSelect(deal)) return;
   if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol ||
      HistoryDealGetInteger(deal, DEAL_MAGIC) != (long)RecoveryMagic_)
      return;
   long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
   if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY) return;
   g_t165GuardRealized += Recovery_T165DealCash(deal);
   Recovery_T165GuardRememberDeal(deal);
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
   datetime dayStart = StringToTime(TimeToString(now, TIME_DATE));
   if(!g_t165GuardSeeded || g_t165GuardDayStart != dayStart)
      m.historyOk = Recovery_T165SeedRealizedCache(now);
   if(m.historyOk)
      m.recoveryRealizedToday = g_t165GuardRealized;
   return m.historyOk;
}

#endif // BD_RECOVERY_T165_GUARD_SCOPE_MQH
