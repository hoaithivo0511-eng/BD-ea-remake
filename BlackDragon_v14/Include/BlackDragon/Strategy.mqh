//+------------------------------------------------------------------+
//| Strategy.mqh — BlackDragon v14.8.0                               |
//| Purpose   : Composition root / coordinator. Turns signals +      |
//|             basket state into TradeIntents and hands them to     |
//|             ExecutionLayer. (Addition vs Plan v2 file list —     |
//|             keeps BlackDragon.mq5 under 200 lines.)              |
//| Invariants: Reads engines' outputs; never touches chart objects; |
//|             never calls OrderSend directly.                      |
//| Depends on: Types, GridEngine, EntryFilters, ExitEngine,         |
//|             BasketManager, ExecutionLayer, Panel                 |
//| [STRATEGY-BEHAVIOR] Gating conditions mirror v13 except the      |
//|  retired legacy hour filter; spread gates only the first order.  |
//|  Detailed TimeLocal schedule is registered from OnInit.          |
//|  - grid adds are gated by pause/news/one-per-bar/MinuteStop only |
//|  - BD-R9 (v14.7.2): hedge OFF gates only a NEW series, not a     |
//|    DCA add. Gating both deadlocked both sides (EntryFilters).    |
//+------------------------------------------------------------------+
#ifndef BD_STRATEGY_MQH
#define BD_STRATEGY_MQH
#include "Types.mqh"
#include "GridEngine.mqh"
#include "EntryFilters.mqh"
#include "ExitEngine.mqh"
#include "BasketManager.mqh"
#include "ExecutionLayer.mqh"
#include "MoneyGuard.mqh"
#include "Panel.mqh"

class CStrategy
{
private:
   CBasketManager    *m_basket;
   CExecutionLayer   *m_exec;
   ILotSizer         *m_sizer;
   CMoneyGuard       *m_guard;    // FE-401/402 (v14.3), NULL = disabled
   CDistancePlan     *m_dist;     // FE-407 (v14.7): classic or manual pip chain
   CVirtualExitPolicy m_exitPolicy;
   CFilterChain       m_newSeriesFilters;  // spread + pause + news (+ extensions)
   CFilterChain       m_gridFilters;       // pause + news (v13 behavior)

   //--- v13: first order of a series --------------------------------
   void TryOpenSeries(const EAContext &ctx)
   {
      // [STRATEGY-BEHAVIOR] v13 GET_INFO: with hedge OFF an open basket on one
      // side blocks a NEW SERIES on the opposite side (Flag_Open_Buy/Sell=false).
      // BD-R9 (v14.7.2): this is the ONLY place the hedge flag gates an open.
      bool hedgeAllowsBuy  = Hedge_AllowsNewSeries(Flag_Use_hedge, m_basket.sell.count);
      bool hedgeAllowsSell = Hedge_AllowsNewSeries(Flag_Use_hedge, m_basket.buy.count);
      // BUY
      if(Cfg.TradeBuy && ctx.signalBuy && m_basket.buy.count == 0 && Cfg.NewCycle &&
         hedgeAllowsBuy &&
         m_basket.LastBuyBar() != ctx.barTime && !m_exec.BusyOpen(BD_DIR_BUY) &&
         m_newSeriesFilters.Allow(ctx, BD_DIR_BUY))
      {
         if(m_exec.OpenMarket(BD_DIR_BUY, m_sizer.FirstLot(), 1)) m_basket.Invalidate();   // FE-203: series order #1
      }
      // SELL
      if(Cfg.TradeSell && ctx.signalSell && m_basket.sell.count == 0 && Cfg.NewCycle &&
         hedgeAllowsSell &&
         m_basket.LastSellBar() != ctx.barTime && !m_exec.BusyOpen(BD_DIR_SELL) &&
         m_newSeriesFilters.Allow(ctx, BD_DIR_SELL))
      {
         if(m_exec.OpenMarket(BD_DIR_SELL, m_sizer.FirstLot(), 1)) m_basket.Invalidate();  // FE-203: series order #1
      }
   }

   //--- v13: martingale grid adds ------------------------------------
   void TryGridAdd(const EAContext &ctx, BasketSide &side, const int dir, const int maxOrders)
   {
      if(side.count <= 0 || side.count >= maxOrders) return;
      datetime lastBar = (dir == BD_DIR_BUY) ? m_basket.LastBuyBar() : m_basket.LastSellBar();
      if(lastBar == ctx.barTime) return;                       // max 1 order per bar per side
      if(m_exec.BusyOpen(dir)) return;                         // async slot in flight (fix #6)
      if(!m_gridFilters.Allow(ctx, dir)) return;               // pause + news only (v13)
      PositionInfo last = side.pos[side.count - 1];
      if(MinuteStop != 0 && ctx.now <= last.openTime + MinuteStop * 60) return;

      // FE-407: distance table via the plan (classic v13 formula or manual
      // pip chain); FE-201 PointScale applies identically to both.
      int dist = m_dist.DistancePoints(side.count) * Cfg.PointScale;
      bool hit = (dir == BD_DIR_BUY)
         ? (ctx.ask <= last.openPrice - dist * ctx.point)      // [STRATEGY-BEHAVIOR]
         : (ctx.bid >= last.openPrice + dist * ctx.point);
      if(!hit) return;

      if(m_exec.OpenMarket(dir, m_sizer.NextLot(side), side.count + 1)) m_basket.Invalidate();  // FE-203
   }

   //--- Exit decisions -> execution ------------------------------------
   bool ApplyExit(const EAContext &ctx, BasketSide &side, const int dir)
   {
      ExitDecision d = m_exitPolicy.Check(ctx, side, dir);
      if(d.kind == EXIT_NONE) return false;
      if(d.kind == EXIT_OVERLAP)
      {
         Log_Info("Strategy", "Overlap close: last " + (string)d.pairLast + " + first " + (string)d.pairFirst);
         m_exec.ClosePosition(d.pairLast);   // v13 order: last first
         m_exec.ClosePosition(d.pairFirst);
      }
      else
      {
         string why = d.kind == EXIT_TP ? "virtual TP" : d.kind == EXIT_SL ? "virtual SL" : "virtual trailing";
         Log_Info("Strategy", "Basket close (" + why + ") dir=" + (string)dir + " positions=" + (string)side.count);
         m_exec.CloseBasket(side);
      }
      m_basket.Invalidate();
      return true;   // BD-001: a close decision is terminal for this tick
   }

   //--- v13 TP_SL_TRAIL: push real SL/TP onto positions -----------------
   void ApplyRealLevels(const EAContext &ctx, const BasketSide &side, const bool isBuy)
   {
      double sl, tp;
      if(!m_exitPolicy.RealLevels(ctx, side, isBuy, sl, tp)) return;
      // BD-R3 (v14.7.2, quyet dinh Chu nha 11/08/2026): after a DCA add the
      // trail re-arms from the NEW breakeven, so an already-armed trailing SL
      // is intentionally dropped (sl=0) until it arms again. Dropping real
      // broker-side protection must never be silent — announce it once per
      // side (Log_Warn is throttled 60s) so it is visible in the journal.
      if(sl == 0 && Trail_Mode == mode_Real && !side.trailArmed)
      {
         bool hadStop = false;
         for(int i = 0; i < side.count; i++)
            if(NormalizeDouble(side.pos[i].sl, ctx.digits) != 0) { hadStop = true; break; }
         if(hadStop)
            Log_Warn("Strategy", "trailclr", "real trailing SL cleared on " + (string)side.count + " " +
                     (isBuy ? "buy" : "sell") + " position(s) — trail re-arms from the new breakeven " +
                     DoubleToString(side.breakeven, ctx.digits));
      }
      bool modified = false;
      for(int i = 0; i < side.count; i++)
      {
         double curSl = NormalizeDouble(side.pos[i].sl, ctx.digits);
         double curTp = NormalizeDouble(side.pos[i].tp, ctx.digits);
         if(curSl != sl || curTp != tp)
         {
            // FIX-4 (14.2.1): a modify already in flight is NOT a failure —
            // skip quietly instead of logging a misleading warn every tick.
            if(m_exec.HasPendingModify(side.pos[i].ticket)) continue;
            if(m_exec.ModifySlTp(side.pos[i].ticket, sl, tp)) modified = true;
            else Log_Warn("Strategy", "sltp", "modify SL/TP failed ticket " + (string)side.pos[i].ticket);
         }
      }
      // audit fix: refresh cached sl/tp, otherwise the same modify is re-sent every tick
      if(modified) m_basket.Invalidate();
   }

   //--- FE-401/402 (v14.3): money guard decisions -> execution -----------
   //    Runs BEFORE the regular exits: these are risk controls with wider
   //    scope. MoneyGuard only decides; all trade calls stay here/exec.
   bool ApplyGuard(const EAContext &ctx)
   {
      if(m_guard == NULL) return false;
      bool   bothOpen = m_basket.buy.count > 0 && m_basket.sell.count > 0;
      double dayNet   = m_basket.DayProfit() + m_basket.buy.totalProfit + m_basket.sell.totalProfit;
      eGuardAction a  = m_guard.Check(ctx.now, m_basket.buy.totalProfit, m_basket.sell.totalProfit,
                                      bothOpen, dayNet, m_basket.DayStartBalance());
      if(a == GUARD_NONE) return false;
      if(a == GUARD_CLOSE_ACCOUNT)
         m_exec.CloseAllAccount();
      else if(a == GUARD_CLOSE_BUY)
         m_exec.CloseBasket(m_basket.buy);
      else if(a == GUARD_CLOSE_SELL)
         m_exec.CloseBasket(m_basket.sell);
      else   // GUARD_CLOSE_MAGIC / GUARD_CLOSE_MAGIC_DAILY
      {
         m_exec.CloseBasket(m_basket.buy);
         m_exec.CloseBasket(m_basket.sell);
      }
      m_basket.Invalidate();
      return true;   // BD-001: widest-scope close suppresses all later work
   }

public:
   void Init(CBasketManager *basket, CExecutionLayer *exec, ILotSizer *sizer,
             CMoneyGuard *guard, CDistancePlan *dist)
   {
      m_basket = basket;
      m_exec   = exec;
      m_sizer  = sizer;
      m_guard  = guard;
      m_dist   = dist;
      // Registration point: ALL enabled behaviors are visible right here.
      m_newSeriesFilters.Add(new CSpreadFilter());
      m_newSeriesFilters.Add(new CPauseFilter());
      m_newSeriesFilters.Add(new CNewsFilter());
      m_gridFilters.Add(new CPauseFilter());
      m_gridFilters.Add(new CNewsFilter());
   }

   void AddNewSeriesFilter(IEntryFilter *f) { m_newSeriesFilters.Add(f); }  // P5 extension point
   void AddGridFilter(IEntryFilter *f)      { m_gridFilters.Add(f); }       // v14.3: FE-402 halt filter needs the grid chain too

   void OnTick(const EAContext &ctx, CPanel &panel)
   {
      // 1. Consume all one-shot panel requests up front. An open clicked while
      //    any close path is active is discarded, never queued for a later tick.
      bool panelCloseBuy  = panel.TakeCloseBuy();
      bool panelCloseSell = panel.TakeCloseSell();
      bool panelOpenBuy   = panel.TakeOpenBuy();
      bool panelOpenSell  = panel.TakeOpenSell();

      bool panelClose = false;
      if(panelCloseBuy && m_basket.buy.count > 0)
      {
         m_exec.CloseBasket(m_basket.buy);
         m_basket.Invalidate();
         panelClose = true;
      }
      if(panelCloseSell && m_basket.sell.count > 0)
      {
         m_exec.CloseBasket(m_basket.sell);
         m_basket.Invalidate();
         panelClose = true;
      }
      if(panelClose)
      {
         if(panelOpenBuy || panelOpenSell)
            Log_Warn("Strategy", "panelclosewins", "panel open ignored because a panel close is active");
         return;   // BD-001: no open/DCA/modify after a panel close
      }

      // A close sent on an earlier tick remains terminal until ExecutionLayer
      // observes/reconciles its broker state (BD-002).
      // BD-R1 (v14.7.2, quyet dinh Chu nha 11/08/2026): this ordering STAYS —
      // MoneyGuard deliberately does NOT run above this early return, because
      // a guard close fired while an earlier close is unresolved would double
      // the exit traffic. The exposure it creates (money/daily stops frozen
      // while an async close hangs) is bounded instead, in
      // ExecutionLayer::Watchdog: BD_ASYNC_CLOSE_HARD_TIMEOUT_SEC = 10s for a
      // CLOSE/MODIFY, down from the 30s shared with OPEN intents.
      if(m_exec.HasAnyPendingClose())
      {
         if(panelOpenBuy || panelOpenSell)
            Log_Warn("Strategy", "pendingclose", "panel open ignored while an async close is pending");
         return;
      }

      // 1.5 FE-401/402: widest-scope risk exits run before every open path.
      if(ApplyGuard(ctx))
      {
         if(panelOpenBuy || panelOpenSell)
            Log_Warn("Strategy", "guardclose", "panel open ignored because a money guard close fired");
         return;   // BD-001: guard close ends the tick
      }

      // 2. Evaluate BOTH directions so simultaneous exits can both be sent,
      //    then terminate before entries/real-level modifications.
      bool exitBuy  = ApplyExit(ctx, m_basket.buy,  BD_DIR_BUY);
      bool exitSell = ApplyExit(ctx, m_basket.sell, BD_DIR_SELL);
      if(exitBuy || exitSell)
      {
         if(panelOpenBuy || panelOpenSell)
            Log_Warn("Strategy", "basketclose", "panel open ignored because a basket exit fired");
         return;   // BD-001
      }

      // FE-203: manual panel orders join the basket -> numbered as next DCA order.
      // FIX-3 (14.2.1): in async mode a click while an open request is in
      // flight would double the order (and its number) — respect the busy flag.
      // NOTE (BD-R9): these two clicks are the reason two-sided exposure is
      // reachable even with Flag_Use_hedge = false — the panel deliberately
      // obeys the operator, not the hedge flag.
      if(panelOpenBuy)
      {
         if(m_exec.BusyOpen(BD_DIR_BUY)) Log_Warn("Strategy", "panelbusy", "panel Open Buy ignored: async open in flight");
         else if(m_exec.OpenMarket(BD_DIR_BUY, Cfg.EditLot, m_basket.buy.count + 1)) m_basket.Invalidate();
      }
      if(panelOpenSell)
      {
         if(m_exec.BusyOpen(BD_DIR_SELL)) Log_Warn("Strategy", "panelbusy", "panel Open Sell ignored: async open in flight");
         else if(m_exec.OpenMarket(BD_DIR_SELL, Cfg.EditLot, m_basket.sell.count + 1)) m_basket.Invalidate();
      }

      // 3. entries
      TryOpenSeries(ctx);
      // BD-R9 (v14.7.2): NO hedge gate here. The old form was
      //    if(Flag_Use_hedge || m_basket.sell.count == 0) TryGridAdd(buy)
      //    if(Flag_Use_hedge || m_basket.buy.count  == 0) TryGridAdd(sell)
      // whose two conditions are mutually exclusive: with hedge OFF and both
      // sides open, EVERY DCA add on BOTH sides was blocked forever while the
      // exits kept running. See Hedge_AllowsGridAdd in EntryFilters.mqh.
      if(Hedge_AllowsGridAdd(m_basket.buy.count))  TryGridAdd(ctx, m_basket.buy,  BD_DIR_BUY,  MaxOrdersBuy);
      if(Hedge_AllowsGridAdd(m_basket.sell.count)) TryGridAdd(ctx, m_basket.sell, BD_DIR_SELL, MaxOrdersSell);

      // 4. real-mode stops
      ApplyRealLevels(ctx, m_basket.buy,  true);
      ApplyRealLevels(ctx, m_basket.sell, false);
   }

   void Deinit()
   {
      m_newSeriesFilters.Clear();
      m_gridFilters.Clear();
   }
};
#endif // BD_STRATEGY_MQH
