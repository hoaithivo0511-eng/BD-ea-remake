//+------------------------------------------------------------------+
//| RecoveryT165GuardScope.mqh — T16.5 Guard scope coherence         |
//| Reads RecoveryMagic exposure using the same Core-direction owner |
//| mapping that the Recovery exit coordinator mutates.              |
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_T165_GUARD_SCOPE_MQH
#define BD_RECOVERY_T165_GUARD_SCOPE_MQH

#include "RecoveryT165Policy.mqh"

struct SRecoveryT165GuardMetrics
{
   double recoveryForBuyFloating;   // SELL Recovery Hedge owned by BUY Core
   double recoveryForSellFloating;  // BUY Recovery Hedge owned by SELL Core
   double recoveryRealizedToday;
   bool   buyRecoveryOpen;
   bool   sellRecoveryOpen;
   bool   historyOk;
};

void Recovery_T165GuardMetricsReset(SRecoveryT165GuardMetrics &m)
{
   m.recoveryForBuyFloating  = 0.0;
   m.recoveryForSellFloating = 0.0;
   m.recoveryRealizedToday   = 0.0;
   m.buyRecoveryOpen         = false;
   m.sellRecoveryOpen        = false;
   m.historyOk               = true;
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
         // SELL Recovery Hedge protects BUY Core.
         m.recoveryForBuyFloating += cash;
         m.buyRecoveryOpen = true;
      }
      else if(type == POSITION_TYPE_BUY)
      {
         // BUY Recovery Hedge protects SELL Core.
         m.recoveryForSellFloating += cash;
         m.sellRecoveryOpen = true;
      }
   }
}

bool Recovery_T165ReadRecoveryRealizedToday(const datetime now,
                                            const string symbol,
                                            const long recoveryMagic,
                                            double &cashOut)
{
   cashOut = 0.0;
   datetime dayStart = StringToTime(TimeToString(now, TIME_DATE));
   if(!HistorySelect(dayStart, now + 1)) return false;

   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0) continue;
      if(HistoryDealGetString(deal, DEAL_SYMBOL) != symbol ||
         HistoryDealGetInteger(deal, DEAL_MAGIC) != recoveryMagic)
         continue;
      long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY) continue;
      cashOut += HistoryDealGetDouble(deal, DEAL_PROFIT)
               + HistoryDealGetDouble(deal, DEAL_SWAP)
               + HistoryDealGetDouble(deal, DEAL_COMMISSION)
               + HistoryDealGetDouble(deal, DEAL_FEE);
   }
   return true;
}

bool Recovery_T165ReadGuardMetrics(const datetime now,
                                   SRecoveryT165GuardMetrics &m)
{
   Recovery_T165GuardMetricsReset(m);
   if(RecoveryMode_ != recovery_ACTIVE || RecoveryMagic_ <= 0)
      return true;

   Recovery_T165ReadRecoveryFloating(_Symbol, (long)RecoveryMagic_, m);
   m.historyOk = Recovery_T165ReadRecoveryRealizedToday(now, _Symbol,
                                                        (long)RecoveryMagic_,
                                                        m.recoveryRealizedToday);
   return m.historyOk;
}

#endif // BD_RECOVERY_T165_GUARD_SCOPE_MQH
