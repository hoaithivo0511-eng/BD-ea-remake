//+------------------------------------------------------------------+
//| BasketManager.mqh — BlackDragon v14.0.0                          |
//| Purpose   : OWNS BasketState. Event-driven position cache        |
//|             (C1: no full scan per tick), breakeven & levels.     |
//| Inputs    : position pool, trade events                          |
//| Outputs   : buy/sell BasketSide (read-only for engines)          |
//| Invariants: The ONLY writer of BasketState. Rebuild happens on   |
//|             Invalidate() (trade transaction) — not every tick.   |
//| Fixes     : #3 signed swap (+opt. commission), #4 dynamic array  |
//|             no 600 cap, #5 explicit sort by time+ticket,         |
//|             #8 tick_value<=0 guard, C2 event-driven day profit,  |
//|             C4 incremental trail extreme (no CopyHigh per tick), |
//|             AU-14-01 floating profit/swap refreshed EVERY tick   |
//|             (C1 caches only event-static data; profit moves with |
//|             price -> stale cache killed Overlap + panel P/L),    |
//|             BD-R7 vanished tickets compacted out immediately.    |
//| Depends on: Types.mqh, Logger.mqh                                |
//+------------------------------------------------------------------+
#ifndef BD_BASKETMANAGER_MQH
#define BD_BASKETMANAGER_MQH
#include "Types.mqh"
#include "Logger.mqh"

//--- PURE breakeven formula (unit-tested in Tests/RunTests.mq5) ------
//    fix #3: SIGNED cost (v13 used MathAbs -> wrong side on positive swap)
//    fix #8: tickValue<=0 -> no shift (symbol data not synchronized yet)
double Basket_Breakeven(const double avgOpen, const double totalLots, const double costMoney,
                        const double tickValue, const double point, const bool isBuy)
{
   if(totalLots <= 0) return 0;
   double shift = 0;
   if(tickValue > 0) shift = costMoney / (tickValue * totalLots) * point;
   return isBuy ? avgOpen - shift : avgOpen + shift;
}

class CBasketManager
{
private:
   bool     m_dirty;
   double   m_dayProfit;
   datetime m_dayStart;
   datetime m_lastBuyBar;    // v13: tLastBuy  (max 1 order per bar per side)
   datetime m_lastSellBar;   // v13: tLastSell
   double   m_commissionBuy;
   double   m_commissionSell;
   double   m_dayStartBalance;   // FE-402: balance at day start (for % daily targets)
public:
   BasketSide buy;
   BasketSide sell;

   CBasketManager() : m_dirty(true), m_dayProfit(0), m_dayStart(0),
                      m_lastBuyBar(0), m_lastSellBar(0),
                      m_commissionBuy(0), m_commissionSell(0),
                      m_dayStartBalance(0) {}

   datetime LastBuyBar()  const { return m_lastBuyBar;  }
   datetime LastSellBar() const { return m_lastSellBar; }
   double   DayProfit()   const { return m_dayProfit;   }
   double   DayStartBalance() const { return m_dayStartBalance; }   // FE-402

   void Invalidate() { m_dirty = true; }

   //--- C2: called once from OnInit and on day rollover ---------------
   void SeedDayProfit()
   {
      m_dayStart  = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
      m_dayProfit = 0;
      if(!HistorySelect(m_dayStart, TimeCurrent() + 1))
      {
         m_dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);   // FE-402 fallback
         return;
      }
      for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
      {
         ulong tic = HistoryDealGetTicket(i);
         if(tic == 0) continue;
         if(HistoryDealGetInteger(tic, DEAL_MAGIC) == Magic &&
            HistoryDealGetString(tic, DEAL_SYMBOL) == _Symbol &&
            HistoryDealGetInteger(tic, DEAL_ENTRY) == DEAL_ENTRY_OUT)
            m_dayProfit += HistoryDealGetDouble(tic, DEAL_PROFIT)
                         + HistoryDealGetDouble(tic, DEAL_SWAP)
                         + HistoryDealGetDouble(tic, DEAL_COMMISSION);
      }
      // FE-402: balance at day start = current balance minus what THIS bot
      // already realized today (deposits/withdrawals mid-day would skew this
      // — documented limitation).
      m_dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE) - m_dayProfit;
   }

   //--- C2: called from OnTradeTransaction on DEAL_ENTRY_OUT ----------
   void OnDealClosed(const double profit, const double swap, const double commission)
   {
      m_dayProfit += profit + swap + commission;
   }

   void CheckDayRollover(const datetime now)
   {
      if(now - m_dayStart >= 86400) SeedDayProfit();
   }

   //--- Per tick: cheap. Full rebuild only when dirty (C1) ------------
   //    BD-R7 (v14.7.2): RefreshFloating() is where a cached ticket is
   //    discovered to be gone (closed by the broker, by hand, or by another
   //    EA). It used to only raise m_dirty, so the REST of this tick still
   //    ran on a basket whose count/totalLots included a dead position:
   //    breakeven, TP/SL and Overlap were all computed from stale data for
   //    one full tick. Now the dead entries are dropped on the spot and, if
   //    anything was dropped, we rebuild once and refresh again. Bounded to
   //    2 passes: the second pass runs on a freshly rebuilt cache, so it can
   //    only catch tickets that died in the last microseconds — those are
   //    handled next tick, exactly as before. No unbounded loop per tick.
   void Update(const EAContext &ctx)
   {
      for(int pass = 0; pass < 2; pass++)
      {
         if(m_dirty) Rebuild(ctx);
         bool droppedBuy  = RefreshFloating(buy);   // AU-14-01: profit/swap move with price -> re-read per tick
         bool droppedSell = RefreshFloating(sell);
         if(!droppedBuy && !droppedSell) break;
      }
      UpdateExtremes(ctx);       // C4: O(1) per tick
      ComputeLevels(ctx);        // arithmetic only, no API scans
   }

private:
   void Rebuild(const EAContext &ctx)
   {
      m_dirty = false;
      ResetSide(buy);
      ResetSide(sell);
      m_commissionBuy  = 0;
      m_commissionSell = 0;

      int total = PositionsTotal();
      for(int i = 0; i < total; i++)
      {
         ulong tic = PositionGetTicket(i);
         if(tic == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         long magic = PositionGetInteger(POSITION_MAGIC);
         if(!(magic == Magic || (magic == 0 && flag_Hand_Ord))) continue;

         PositionInfo p;
         p.ticket    = tic;
         p.type      = (int)PositionGetInteger(POSITION_TYPE);
         p.openPrice = NormalizeDouble(PositionGetDouble(POSITION_PRICE_OPEN), ctx.digits);
         p.lots      = PositionGetDouble(POSITION_VOLUME);
         p.profit    = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
         p.tp        = PositionGetDouble(POSITION_TP);
         p.sl        = PositionGetDouble(POSITION_SL);
         p.openTime  = (datetime)PositionGetInteger(POSITION_TIME);

         if(p.type == POSITION_TYPE_BUY)
         {
            Append(buy, p);
            if(p.openTime >= ctx.barTime) m_lastBuyBar = ctx.barTime;   // v13 tLastBuy
         }
         else
         {
            Append(sell, p);
            if(p.openTime >= ctx.barTime) m_lastSellBar = ctx.barTime;  // v13 tLastSell
         }
      }
      SortSide(buy);   // fix #5: never rely on pool ordering
      SortSide(sell);

      if(UseCommissionInBE)   // rebuild-only history lookups (cheap: event-driven)
      {
         m_commissionBuy  = SumCommission(buy);
         m_commissionSell = SumCommission(sell);
      }
      SeedExtreme(buy,  ctx, true);
      SeedExtreme(sell, ctx, false);
   }

   void ResetSide(BasketSide &s)
   {
      s.count = 0; s.totalLots = 0; s.totalProfit = 0;
      s.breakeven = 0; s.tpLevel = 0; s.slLevel = 0;
      s.trailLevel = 0; s.trailArmed = false;
      s.swapSum = 0;
      ArrayResize(s.pos, 0);
   }

   //--- AU-14-01: C1 may cache only event-static data (tickets, lots, open
   //    price, open time). Floating profit and swap change with every tick,
   //    so they are re-read here — one PositionSelectByTicket per cached
   //    ticket, the same per-tick API cost as the SwapSum() this replaces.
   //    Consumers: Exit_OverlapHit (pos[].profit) and the panel (totalProfit).
   //    BD-R7: a ticket that no longer exists is compacted out of the array
   //    IN PLACE (write index w) and count/totalLots/totalProfit/swapSum are
   //    rebuilt from the survivors, so no consumer downstream in this tick
   //    can size a decision on a position that is already closed. Returns
   //    true when at least one entry was dropped.
   bool RefreshFloating(BasketSide &s)
   {
      if(s.count == 0) return false;
      double totalProfit = 0, swapSum = 0, totalLots = 0;
      int w = 0;                       // write index for in-place compaction
      for(int i = 0; i < s.count; i++)
      {
         if(!PositionSelectByTicket(s.pos[i].ticket))
         {
            m_dirty = true;            // ticket gone (closed elsewhere) -> rebuild
            continue;                  // BD-R7: and drop it from the cache NOW
         }
         double swap = PositionGetDouble(POSITION_SWAP);
         s.pos[w] = s.pos[i];
         s.pos[w].profit = PositionGetDouble(POSITION_PROFIT) + swap;  // v13 semantics: profit incl. swap
         totalProfit += s.pos[w].profit;
         swapSum     += swap;
         totalLots   += s.pos[w].lots;
         w++;
      }
      bool dropped  = (w != s.count);
      s.count       = w;
      s.totalLots   = totalLots;
      s.totalProfit = totalProfit;
      s.swapSum     = swapSum;
      if(dropped) ArrayResize(s.pos, w);
      return dropped;
   }

   void Append(BasketSide &s, const PositionInfo &p)
   {
      ArrayResize(s.pos, s.count + 1);   // fix #4: dynamic, no 600 cap
      s.pos[s.count] = p;
      s.count++;
      s.totalLots   += p.lots;
      s.totalProfit += p.profit;
   }

   void SortSide(BasketSide &s)   // insertion sort by (openTime, ticket), oldest first
   {
      for(int i = 1; i < s.count; i++)
      {
         PositionInfo key = s.pos[i];
         int j = i - 1;
         while(j >= 0 && (s.pos[j].openTime > key.openTime ||
               (s.pos[j].openTime == key.openTime && s.pos[j].ticket > key.ticket)))
         {
            s.pos[j + 1] = s.pos[j];
            j--;
         }
         s.pos[j + 1] = key;
      }
   }

   double SumCommission(const BasketSide &s)
   {
      double sum = 0;
      for(int i = 0; i < s.count; i++)
         if(HistorySelectByPosition(s.pos[i].ticket))
            for(int d = HistoryDealsTotal() - 1; d >= 0; d--)
            {
               ulong dt = HistoryDealGetTicket(d);
               if(dt != 0) sum += HistoryDealGetDouble(dt, DEAL_COMMISSION);
            }
      return sum;
   }

   void SeedExtreme(BasketSide &s, const EAContext &ctx, const bool isBuy)
   {
      // C4: seed once from bar history since last order; then O(1) per tick.
      s.extremePrice = isBuy ? 0 : DBL_MAX;
      if(s.count == 0 || Cfg.TrailStart == 0) return;
      double arr[];
      int bars = isBuy
         ? CopyHigh(_Symbol, PERIOD_CURRENT, s.pos[s.count-1].openTime, ctx.now, arr)
         : CopyLow (_Symbol, PERIOD_CURRENT, s.pos[s.count-1].openTime, ctx.now, arr);
      if(bars > 0)
         s.extremePrice = isBuy ? arr[ArrayMaximum(arr, 0, bars)] : arr[ArrayMinimum(arr, 0, bars)];
   }

   void UpdateExtremes(const EAContext &ctx)
   {
      if(buy.count  > 0) buy.extremePrice  = MathMax(buy.extremePrice,  ctx.bid);
      if(sell.count > 0) sell.extremePrice = MathMin(sell.extremePrice, ctx.bid);
   }

   //--- [STRATEGY-BEHAVIOR] v13 level formulas (with bug #3/#8 fixes) --
   void ComputeLevels(const EAContext &ctx)
   {
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      ComputeSide(buy,  ctx, tickValue, true,  m_commissionBuy);
      ComputeSide(sell, ctx, tickValue, false, m_commissionSell);
   }

   void ComputeSide(BasketSide &s, const EAContext &ctx, const double tickValue,
                    const bool isBuy, const double commission)
   {
      s.breakeven = 0; s.tpLevel = 0; s.slLevel = 0;
      s.trailLevel = 0; s.trailArmed = false;
      if(s.count == 0) return;

      // weighted average open
      double wsum = 0;
      for(int i = 0; i < s.count; i++) wsum += s.pos[i].openPrice * s.pos[i].lots;
      double swapSum = s.swapSum;   // AU-14-01: refreshed this tick in RefreshFloating()

      if(s.totalLots <= 0) return;
      double avg = wsum / s.totalLots;

      if(tickValue <= 0)
         Log_Warn("Basket", "tickval", "SYMBOL_TRADE_TICK_VALUE<=0, skipping cost shift this tick");
      s.breakeven = Basket_Breakeven(avg, s.totalLots, swapSum + commission, tickValue, ctx.point, isBuy);

      if(Cfg.TP != 0) s.tpLevel = isBuy ? s.breakeven + Cfg.TP * ctx.point
                                        : s.breakeven - Cfg.TP * ctx.point;
      if(Cfg.SL != 0) s.slLevel = isBuy ? s.pos[0].openPrice - Cfg.SL * ctx.point
                                        : s.pos[0].openPrice + Cfg.SL * ctx.point;

      // [STRATEGY-BEHAVIOR] trail only if TrailStart!=0 and (TrailStart<TP or TP==0)
      if(Cfg.TrailStart != 0 && (Cfg.TrailStart < Cfg.TP || Cfg.TP == 0))
      {
         if(isBuy)
         {
            if(s.extremePrice > s.breakeven + Cfg.TrailStart * ctx.point)
            { s.trailLevel = s.extremePrice - Cfg.TrailDistance * ctx.point; s.trailArmed = true; }
            else
            { s.trailLevel = s.breakeven + Cfg.TrailStart * ctx.point; s.trailArmed = false; }
         }
         else
         {
            // v13 adds current spread to the sell arming threshold
            if(s.extremePrice != DBL_MAX &&
               s.extremePrice < s.breakeven - (Cfg.TrailStart + ctx.spreadPoints) * ctx.point)
            { s.trailLevel = s.extremePrice + Cfg.TrailDistance * ctx.point; s.trailArmed = true; }
            else
            { s.trailLevel = s.breakeven - Cfg.TrailStart * ctx.point; s.trailArmed = false; }
         }
      }
   }
};
#endif // BD_BASKETMANAGER_MQH
