//+------------------------------------------------------------------+
//| Strategy.mqh — BlackDragon v14.8.0                               |
//| Purpose   : Composition root / coordinator. Turns signals +      |
//|             basket state into TradeIntents and hands them to     |
//|             ExecutionLayer.                                     |
//| Invariants: Reads engines' outputs; never touches chart objects; |
//|             never calls OrderSend directly.                      |
//| Depends on: Types, GridEngine, EntryFilters, ExitEngine,         |
//|             BasketManager, ExecutionLayer, Panel                 |
//| [STRATEGY-BEHAVIOR]                                              |
//|  - spread filter gates ONLY the first order of a series          |
//|  - detailed TimeLocal schedule is registered from OnInit         |
//|  - grid adds are gated by pause/news/one-per-bar/MinuteStop      |
//|  - hedge OFF gates only a NEW series, not a DCA add              |
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
   CBasketManager     *m_basket;
   CExecutionLayer    *m_exec;
   ILotSizer          *m_sizer;
   CMoneyGuard        *m_guard;
   CDistancePlan      *m_dist;
   CVirtualExitPolicy  m_exitPolicy;
   CFilterChain        m_newSeriesFilters;
   CFilterChain        m_gridFilters;

   void TryOpenSeries(const EAContext &ctx)
   {
      bool hedgeAllowsBuy  = Hedge_AllowsNewSeries(Flag_Use_hedge, m_basket.sell.count);
      bool hedgeAllowsSell = Hedge_AllowsNewSeries(Flag_Use_hedge, m_basket.buy.count);

      if(Cfg.TradeBuy && ctx.signalBuy && m_basket.buy.count == 0 && Cfg.NewCycle &&
         hedgeAllowsBuy &&
         m_basket.LastBuyBar() != ctx.barTime && !m_exec.BusyOpen(BD_DIR_BUY) &&
         m_newSeriesFilters.Allow(ctx, BD_DIR_BUY))
      {
         if(m_exec.OpenMarket(BD_DIR_BUY, m_sizer.FirstLot(), 1)) m_basket.Invalidate();
      }

      if(Cfg.TradeSell && ctx.signalSell && m_basket.sell.count == 0 && Cfg.NewCycle &&
         hedgeAllowsSell &&
         m_basket.LastSellBar() != ctx.barTime && !m_exec.BusyOpen(BD_DIR_SELL) &&
         m_newSeriesFilters.Allow(ctx, BD_DIR_SELL))
      {
         if(m_exec.OpenMarket(BD_DIR_SELL, m_sizer.FirstLot(), 1)) m_basket.Invalidate();
      }
   }

   void TryGridAdd(const EAContext &ctx, BasketSide &side, const int dir, const int maxOrders)
   {
      if(side.count <= 0 || side.count >= maxOrders) return;
      datetime lastBar = (dir == BD_DIR_BUY) ? m_basket.LastBuyBar() : m_basket.LastSellBar();
      if(lastBar == ctx.barTime) return;
      if(m_exec.BusyOpen(dir)) return;
      if(!m_gridFilters.Allow(ctx, dir)) return;

      PositionInfo last = side.pos[side.count - 1];
      if(MinuteStop != 0 && ctx.now <= last.openTime + MinuteStop * 60) return;

      int dist = m_dist.DistancePoints(side.count) * Cfg.PointScale;
      bool hit = (dir == BD_DIR_BUY)
         ? (ctx.ask <= last.openPrice - dist * ctx.point)
         : (ctx.bid >= last.openPrice + dist * ctx.point);
      if(!hit) return;

      if(m_exec.OpenMarket(dir, m_sizer.NextLot(side), side.count + 1)) m_basket.Invalidate();
   }

   bool ApplyExit(const EAContext &ctx, BasketSide &side, const int dir)
   {
      ExitDecision d = m_exitPolicy.Check(ctx, side, dir);
      if(d.kind == EXIT_NONE) return false;
      if(d.kind == EXIT_OVERLAP)
      {
         Log_Info("Strategy", "Overlap close: last " + (string)d.pairLast + " + first " + (string)d.pairFirst);
         m_exec.ClosePosition(d.pairLast);
         m_exec.ClosePosition(d.pairFirst);
      }
      else
      {
         string why = d.kind == EXIT_TP ? "virtual TP" : d.kind == EXIT_SL ? "virtual SL" : "virtual trailing";
         Log_Info("Strategy", "Basket close (" + why + ") dir=" + (string)dir + " positions=" + (string)side.count);
         m_exec.CloseBasket(side);
      }
      m_basket.Invalidate();
      return true;
   }

   void ApplyRealLevels(const EAContext &ctx, const BasketSide &side, const bool isBuy)
   {
      double sl, tp;
      if(!m_exitPolicy.RealLevels(ctx, side, isBuy, sl, tp)) return;

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
            if(m_exec.HasPendingModify(side.pos[i].ticket)) continue;
            if(m_exec.ModifySlTp(side.pos[i].ticket, sl, tp)) modified = true;
            else Log_Warn("Strategy", "sltp", "modify SL/TP failed ticket " + (string)side.pos[i].ticket);
         }
      }
      if(modified) m_basket.Invalidate();
   }

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
      else
      {
         m_exec.CloseBasket(m_basket.buy);
         m_exec.CloseBasket(m_basket.sell);
      }
      m_basket.Invalidate();
      return true;
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

      m_newSeriesFilters.Add(new CSpreadFilter());
      m_newSeriesFilters.Add(new CPauseFilter());
      m_newSeriesFilters.Add(new CNewsFilter());
      m_gridFilters.Add(new CPauseFilter());
      m_gridFilters.Add(new CNewsFilter());
   }

   void AddNewSeriesFilter(IEntryFilter *f) { m_newSeriesFilters.Add(f); }
   void AddGridFilter(IEntryFilter *f)      { m_gridFilters.Add(f); }

   void OnTick(const EAContext &ctx, CPanel &panel)
   {
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
         return;
      }

      if(m_exec.HasAnyPendingClose())
      {
         if(panelOpenBuy || panelOpenSell)
            Log_Warn("Strategy", "pendingclose", "panel open ignored while an async close is pending");
         return;
      }

      if(ApplyGuard(ctx))
      {
         if(panelOpenBuy || panelOpenSell)
            Log_Warn("Strategy", "guardclose", "panel open ignored because a money guard close fired");
         return;
      }

      bool exitBuy  = ApplyExit(ctx, m_basket.buy,  BD_DIR_BUY);
      bool exitSell = ApplyExit(ctx, m_basket.sell, BD_DIR_SELL);
      if(exitBuy || exitSell)
      {
         if(panelOpenBuy || panelOpenSell)
            Log_Warn("Strategy", "basketclose", "panel open ignored because a basket exit fired");
         return;
      }

      if(panelOpenBuy)
      {
         if(m_exec.BusyOpen(BD_DIR_BUY))
            Log_Warn("Strategy", "panelbusy", "panel Open Buy ignored: async open in flight");
         else if(m_exec.OpenMarket(BD_DIR_BUY, Cfg.EditLot, m_basket.buy.count + 1))
            m_basket.Invalidate();
      }
      if(panelOpenSell)
      {
         if(m_exec.BusyOpen(BD_DIR_SELL))
            Log_Warn("Strategy", "panelbusy", "panel Open Sell ignored: async open in flight");
         else if(m_exec.OpenMarket(BD_DIR_SELL, Cfg.EditLot, m_basket.sell.count + 1))
            m_basket.Invalidate();
      }

      TryOpenSeries(ctx);
      if(Hedge_AllowsGridAdd(m_basket.buy.count))
         TryGridAdd(ctx, m_basket.buy, BD_DIR_BUY, MaxOrdersBuy);
      if(Hedge_AllowsGridAdd(m_basket.sell.count))
         TryGridAdd(ctx, m_basket.sell, BD_DIR_SELL, MaxOrdersSell);

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
