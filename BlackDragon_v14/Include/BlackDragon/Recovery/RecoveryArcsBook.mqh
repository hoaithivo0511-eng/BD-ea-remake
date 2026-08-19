//+------------------------------------------------------------------+
//| RecoveryArcsBook.mqh — broker-observable ARCS Core/Hedge book    |
//| Every Recovery position is attributed to its generation comment. |
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_ARCS_BOOK_MQH
#define BD_RECOVERY_ARCS_BOOK_MQH

#include "RecoveryArcsPersistence.mqh"
#include "RecoveryExit.mqh"
#include "RecoveryLock.mqh"
#include "RecoveryBundle.mqh"

struct SArcsPosition
{
   ulong    ticket;
   ulong    positionId;
   datetime openTime;
   long     units;
   double   lots;
   double   openPrice;
   double   sl;
   double   tp;
   double   floatingCash;
   int      generation;
};

struct SArcsLayerSnapshot
{
   long   units;
   double lots;
   double weightedEntry;
   double netBE;
   int    tickets;
};

void Recovery_ArcsSortPositionsOldest(SArcsPosition &items[])
{
   for(int i = 1; i < ArraySize(items); i++)
   {
      SArcsPosition key = items[i];
      int j = i - 1;
      while(j >= 0 &&
            (items[j].openTime > key.openTime ||
             (items[j].openTime == key.openTime && items[j].ticket > key.ticket)))
      {
         items[j + 1] = items[j];
         j--;
      }
      items[j + 1] = key;
   }
}

long Recovery_ArcsCoreType(const eRecoveryCoreDirection dir)
{
   return dir == recovery_CORE_BUY ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
}

long Recovery_ArcsHedgeType(const eRecoveryCoreDirection dir)
{
   return dir == recovery_CORE_BUY ? POSITION_TYPE_SELL : POSITION_TYPE_BUY;
}

long Recovery_ArcsCoreUnits(const eRecoveryCoreDirection dir,
                            const double step)
{
   if(step <= 0.0) return 0;
   long wanted = Recovery_ArcsCoreType(dir);
   long units = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol ||
         PositionGetInteger(POSITION_MAGIC) != (long)Magic ||
         PositionGetInteger(POSITION_TYPE) != wanted)
         continue;
      units += Recovery_VolumeToUnitsFloor(PositionGetDouble(POSITION_VOLUME), step);
   }
   return units;
}

int Recovery_ArcsBuildCore(const eRecoveryCoreDirection dir,
                           const double step,
                           SArcsPosition &out[])
{
   ArrayResize(out, 0);
   if(step <= 0.0) return 0;
   long wanted = Recovery_ArcsCoreType(dir);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol ||
         PositionGetInteger(POSITION_MAGIC) != (long)Magic ||
         PositionGetInteger(POSITION_TYPE) != wanted)
         continue;
      SArcsPosition p;
      ZeroMemory(p);
      p.ticket = ticket;
      p.positionId = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
      p.openTime = (datetime)PositionGetInteger(POSITION_TIME);
      p.lots = PositionGetDouble(POSITION_VOLUME);
      p.units = Recovery_VolumeToUnitsFloor(p.lots, step);
      p.openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      p.sl = PositionGetDouble(POSITION_SL);
      p.tp = PositionGetDouble(POSITION_TP);
      p.floatingCash = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      p.generation = 0;
      if(p.units <= 0 || p.openPrice <= 0.0) continue;
      int n = ArraySize(out);
      ArrayResize(out, n + 1);
      out[n] = p;
   }
   Recovery_ArcsSortPositionsOldest(out);
   return ArraySize(out);
}

double Recovery_ArcsPositionEntryCosts(const ulong positionId)
{
   if(positionId == 0 || !HistorySelectByPosition(positionId)) return 0.0;
   double costs = 0.0;
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0) continue;
      if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol ||
         HistoryDealGetInteger(deal, DEAL_MAGIC) != (long)RecoveryMagic_)
         continue;
      long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_IN && entry != DEAL_ENTRY_INOUT) continue;
      costs += HistoryDealGetDouble(deal, DEAL_COMMISSION) +
               HistoryDealGetDouble(deal, DEAL_FEE);
   }
   return costs;
}

int Recovery_ArcsGenerationFromPositionHistory(const ulong positionId)
{
   if(positionId == 0 || !HistorySelectByPosition(positionId)) return -1;
   ulong best = 0;
   long bestTime = 0;
   int generation = -1;
   for(int i = 0; i < HistoryDealsTotal(); i++)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0) continue;
      if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol ||
         HistoryDealGetInteger(deal, DEAL_MAGIC) != (long)RecoveryMagic_)
         continue;
      long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_IN && entry != DEAL_ENTRY_INOUT) continue;
      string comment = HistoryDealGetString(deal, DEAL_COMMENT);
      int g = Recovery_ArcsGenerationFromComment(comment);
      if(g < 1) continue;
      long t = HistoryDealGetInteger(deal, DEAL_TIME_MSC);
      if(best == 0 || t < bestTime || (t == bestTime && deal < best))
      {
         best = deal;
         bestTime = t;
         generation = g;
      }
   }
   return generation;
}

int Recovery_ArcsPositionGeneration()
{
   string comment = PositionGetString(POSITION_COMMENT);
   int g = Recovery_ArcsGenerationFromComment(comment);
   if(g >= 1) return g;
   ulong positionId = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
   return Recovery_ArcsGenerationFromPositionHistory(positionId);
}

int Recovery_ArcsBuildLayerPositions(const eRecoveryCoreDirection dir,
                                     const int generation,
                                     const double step,
                                     SArcsPosition &out[])
{
   ArrayResize(out, 0);
   if(generation < 1 || step <= 0.0) return 0;
   long wanted = Recovery_ArcsHedgeType(dir);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol ||
         PositionGetInteger(POSITION_MAGIC) != (long)RecoveryMagic_ ||
         PositionGetInteger(POSITION_TYPE) != wanted)
         continue;
      int g = Recovery_ArcsPositionGeneration();
      if(g != generation) continue;

      SArcsPosition p;
      ZeroMemory(p);
      p.ticket = ticket;
      p.positionId = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
      p.openTime = (datetime)PositionGetInteger(POSITION_TIME);
      p.lots = PositionGetDouble(POSITION_VOLUME);
      p.units = Recovery_VolumeToUnitsFloor(p.lots, step);
      p.openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      p.sl = PositionGetDouble(POSITION_SL);
      p.tp = PositionGetDouble(POSITION_TP);
      p.floatingCash = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      p.generation = g;
      if(p.units <= 0 || p.openPrice <= 0.0) continue;
      int n = ArraySize(out);
      ArrayResize(out, n + 1);
      out[n] = p;
   }
   Recovery_ArcsSortPositionsOldest(out);
   return ArraySize(out);
}

long Recovery_ArcsLayerUnits(const eRecoveryCoreDirection dir,
                             const int generation,
                             const double step)
{
   SArcsPosition p[];
   Recovery_ArcsBuildLayerPositions(dir, generation, step, p);
   long units = 0;
   for(int i = 0; i < ArraySize(p); i++) units += p[i].units;
   return units;
}

long Recovery_ArcsTotalHedgeUnits(const eRecoveryCoreDirection dir,
                                  const double step)
{
   if(step <= 0.0) return 0;
   long wanted = Recovery_ArcsHedgeType(dir);
   long units = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol ||
         PositionGetInteger(POSITION_MAGIC) != (long)RecoveryMagic_ ||
         PositionGetInteger(POSITION_TYPE) != wanted)
         continue;
      units += Recovery_VolumeToUnitsFloor(PositionGetDouble(POSITION_VOLUME), step);
   }
   return units;
}

bool Recovery_ArcsLayerSnapshot(const eRecoveryCoreDirection dir,
                                const int generation,
                                const double step,
                                const double tickSize,
                                SArcsPosition &positions[],
                                SArcsLayerSnapshot &snapshot,
                                string &why)
{
   ZeroMemory(snapshot);
   why = "";
   if(Recovery_ArcsBuildLayerPositions(dir, generation, step, positions) <= 0)
   {
      why = "không tìm thấy position của generation ARCS";
      return false;
   }
   double weighted = 0.0;
   double signedCosts = 0.0;
   for(int i = 0; i < ArraySize(positions); i++)
   {
      snapshot.units += positions[i].units;
      snapshot.lots += positions[i].lots;
      weighted += positions[i].openPrice * positions[i].lots;
      signedCosts += PositionSelectByTicket(positions[i].ticket) ? PositionGetDouble(POSITION_SWAP) : 0.0;
      signedCosts += Recovery_ArcsPositionEntryCosts(positions[i].positionId);
   }
   if(snapshot.units <= 0 || snapshot.lots <= 0.0 || tickSize <= 0.0)
   {
      why = "snapshot generation ARCS không hợp lệ";
      return false;
   }
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickValue <= 0.0)
   {
      why = "SYMBOL_TRADE_TICK_VALUE không khả dụng";
      return false;
   }
   snapshot.weightedEntry = weighted / snapshot.lots;
   bool hedgeIsBuy = Recovery_ArcsHedgeType(dir) == POSITION_TYPE_BUY;
   snapshot.netBE = Recovery_NetBreakevenFromCosts(snapshot.weightedEntry,
                                                    snapshot.lots,
                                                    signedCosts,
                                                    tickValue,
                                                    tickSize,
                                                    hedgeIsBuy);
   snapshot.tickets = ArraySize(positions);
   if(snapshot.netBE <= 0.0)
   {
      why = "không tính được hòa vốn ròng generation ARCS";
      return false;
   }
   return true;
}

void Recovery_ArcsBuildCoreCloseCandidates(const eRecoveryCoreDirection dir,
                                           const double step,
                                           SRecoveryCloseCandidate &out[])
{
   ArrayResize(out, 0);
   SArcsPosition core[];
   Recovery_ArcsBuildCore(dir, step, core);
   for(int i = 0; i < ArraySize(core); i++)
   {
      SRecoveryCloseCandidate c;
      c.ticket = core[i].ticket;
      c.openTime = core[i].openTime;
      c.units = core[i].units;
      c.floatingCash = core[i].floatingCash;
      int n = ArraySize(out);
      ArrayResize(out, n + 1);
      out[n] = c;
   }
}

bool Recovery_ArcsThresholdAnchor(const eRecoveryCoreDirection dir,
                                  const double step,
                                  ulong &positionTicket,
                                  double &price,
                                  datetime &openTime)
{
   positionTicket = 0;
   price = 0.0;
   openTime = 0;
   SArcsPosition core[];
   int n = Recovery_ArcsBuildCore(dir, step, core);
   int idx = RecoveryStartAfterDca_;
   if(n <= 0 || idx < 0 || idx >= n) return false;
   positionTicket = core[idx].ticket;
   price = core[idx].openPrice;
   openTime = core[idx].openTime;
   return positionTicket != 0 && price > 0.0;
}

#endif // BD_RECOVERY_ARCS_BOOK_MQH
