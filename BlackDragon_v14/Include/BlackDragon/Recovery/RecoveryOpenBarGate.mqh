// T17.20: read broker evidence immediately before each RH child submission.
// No generation/campaign reset can erase an opening order from this bar.
#ifndef BD_RECOVERY_OPEN_BAR_GATE_MQH
#define BD_RECOVERY_OPEN_BAR_GATE_MQH
#include "RecoveryTypes.mqh"
#include "RecoveryOpenBarPolicy.mqh"

bool Recovery_OneOrderPerBarAllows(const int hedgeDir,
                                  const datetime now,
                                  string &why)
{
   why = "";
   // Preserve the entire OFF path, including no new history/series reads.
   if(!RecoveryOneOrderPerBar_) return true;

   datetime bar = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(hedgeDir < 0 || hedgeDir > 1 || bar <= 0 || now < bar)
   {
      why = "T17.20 RH chờ dữ liệu nến chart hợp lệ";
      return false;
   }
   long barMsc = (long)bar * 1000;
   long wantedPosition = hedgeDir == 0 ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   long wantedDeal = hedgeDir == 0 ? DEAL_TYPE_BUY : DEAL_TYPE_SELL;

   // Covers a just-filled position even before its deal history is exposed.
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetTicket(i) == 0)
      {
         why = "T17.20 RH chờ snapshot vị thế đầy đủ";
         return false;
      }
      if(Recovery_OpenBarEntryMatchesPure(
            PositionGetString(POSITION_SYMBOL) == _Symbol,
            PositionGetInteger(POSITION_MAGIC) == RecoveryMagic_,
            PositionGetInteger(POSITION_TYPE) == wantedPosition, true,
            PositionGetInteger(POSITION_TIME_MSC), barMsc))
      {
         why = "T17.20 RH chờ nến mới: hướng này đã mở một lệnh trong nến";
         return false;
      }
   }

   // Closed BE/SL positions still consume their opening bar. History is also
   // the restart/toggle authority; no transient counter or persisted layout.
   if(!HistorySelect(bar, now))
   {
      why = "T17.20 RH chờ lịch sử giao dịch của nến hiện tại";
      return false;
   }
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0)
      {
         why = "T17.20 RH chờ snapshot deal đầy đủ";
         return false;
      }
      long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
      if(Recovery_OpenBarEntryMatchesPure(
            HistoryDealGetString(deal, DEAL_SYMBOL) == _Symbol,
            HistoryDealGetInteger(deal, DEAL_MAGIC) == RecoveryMagic_,
            HistoryDealGetInteger(deal, DEAL_TYPE) == wantedDeal,
            entry == DEAL_ENTRY_IN || entry == DEAL_ENTRY_INOUT,
            HistoryDealGetInteger(deal, DEAL_TIME_MSC), barMsc))
      {
         why = "T17.20 RH chờ nến mới: lệnh đã đóng BE/SL vẫn tính lượt mở";
         return false;
      }
   }
   return Recovery_OpenBarAllowsPure(true, true, true, false);
}

#endif
