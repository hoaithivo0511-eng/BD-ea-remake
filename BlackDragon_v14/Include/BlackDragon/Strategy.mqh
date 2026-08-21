//+------------------------------------------------------------------+
//| Strategy.mqh — BlackDragon T17 Full Pyramid over T16.6          |
//| Core Pyramid role-aware; DCA/Recovery semantics remain isolated. |
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
#include "Pyramid/CorePyramid.mqh"
#include "Recovery/RecoveryExitCoordinator.mqh"
#include "Recovery/RecoveryT165GuardScope.mqh"
#include "Recovery/RecoveryT165MarginReserve.mqh"

class CStrategy
{
private:
   CBasketManager    *m_basket;
   CExecutionLayer   *m_exec;
   ILotSizer         *m_sizer;
   CMoneyGuard       *m_guard;
   CDistancePlan     *m_dist;
   CRecoveryEngine   *m_recovery;
   CRecoveryExitCoordinator *m_recoveryExit;
   CCorePyramidEngine *m_pyramid;
   CVirtualExitPolicy m_exitPolicy;
   CFilterChain       m_newSeriesFilters;
   CFilterChain       m_gridFilters;

   eRecoveryCoreDirection RecoveryDir(const int dir) const
   {
      return dir == BD_DIR_BUY ? recovery_CORE_BUY : recovery_CORE_SELL;
   }

   eRecoveryExitCoordRequest BeginFullSideClose(const int dir,
                                                const eRecoveryExitCoordReason reason,
                                                const datetime now)
   {
      if(RecoveryMode_ != recovery_ACTIVE) return recovery_EXIT_BYPASS;
      if(m_recoveryExit == NULL) return recovery_EXIT_BLOCKED;
      return m_recoveryExit.BeginFullSideClose(RecoveryDir(dir), reason, now);
   }

   eRecoveryExitCoordRequest BeginTicketClose(const int dir,
                                              const ulong firstTicket,
                                              const ulong secondTicket,
                                              const eRecoveryExitCoordReason reason,
                                              const datetime now)
   {
      if(RecoveryMode_ != recovery_ACTIVE) return recovery_EXIT_BYPASS;
      if(m_recoveryExit == NULL) return recovery_EXIT_BLOCKED;
      return m_recoveryExit.BeginTicketClose(RecoveryDir(dir), firstTicket,
                                             secondTicket, reason, now);
   }

   void DriveRecoveryExit(const datetime now)
   {
      if(m_recoveryExit == NULL || RecoveryMode_ != recovery_ACTIVE) return;
      string why = "";
      m_recoveryExit.Drive(now, why);
      if(why != "")
         Log_WarnEvery("Recovery", "exitcoord", "T8 exit coordination: " + why,
                       Recovery_T165WaitLogSecondsPure(RecoveryWaitLogSeconds_));
   }

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

      // T17 invariant: DCA không được chen vào khi Pyramid legs còn tồn tại.
      // Pyramid LIFO Peel phải tháo optional trend-risk trước.
      if(m_pyramid != NULL && m_pyramid.HasLegs(side)) return;

      BasketSide dcaSide;
      if(m_pyramid != NULL) m_pyramid.BuildDcaView(side, dcaSide);
      else dcaSide = side;
      if(dcaSide.count <= 0) return;

      datetime lastBar = (dir == BD_DIR_BUY) ? m_basket.LastBuyBar() : m_basket.LastSellBar();
      if(lastBar == ctx.barTime) return;
      if(m_exec.BusyOpen(dir)) return;
      if(!m_gridFilters.Allow(ctx, dir)) return;
      PositionInfo last = dcaSide.pos[dcaSide.count - 1];
      if(MinuteStop != 0 && ctx.now <= last.openTime + MinuteStop * 60) return;

      int dist = m_dist.DistancePoints(dcaSide.count) * Cfg.PointScale;
      bool hit = (dir == BD_DIR_BUY)
         ? (ctx.ask <= last.openPrice - dist * ctx.point)
         : (ctx.bid >= last.openPrice + dist * ctx.point);
      if(!hit) return;

      // T17: DCA chain index/sizer nhìn non-Pyramid Core; economic reserve
      // vẫn nhìn FULL Core side (Seed+DCA+Pyramid) qua biến side bên dưới.
      double nextLot = m_sizer.NextLot(dcaSide);
      if(RecoveryMode_ == recovery_ACTIVE && RecoveryDcaMarginReserve_)
      {
         string reserveWhy = "";
         double requiredMargin = 0.0;
         double projectedHedgeLot = 0.0;
         bool futureGenerationAllowed = m_recovery != NULL &&
            m_recovery.T16CanOpenFurtherGeneration(RecoveryDir(dir));
         if(!Recovery_T165ProjectedDcaReserveAllows(dir, side, nextLot,
                                                    futureGenerationAllowed,
                                                    reserveWhy,
                                                    requiredMargin,
                                                    projectedHedgeLot))
         {
            Log_WarnEvery("Recovery", "t165dcareserve" + (string)dir,
                          reserveWhy,
                          Recovery_T165WaitLogSecondsPure(RecoveryWaitLogSeconds_));
            return;
         }
      }

      if(m_exec.OpenMarket(dir, nextLot, dcaSide.count + 1)) m_basket.Invalidate();
   }

   bool ApplyExit(const EAContext &ctx, BasketSide &side, const int dir)
   {
      ExitDecision d = m_exitPolicy.Check(ctx, side, dir);
      if(d.kind == EXIT_NONE) return false;

      // T17: Legacy Overlap không được dùng newest Pyramid leg như một DCA leg.
      // TP/SL/Trail vẫn đóng toàn economic Core basket như trước.
      if(d.kind == EXIT_OVERLAP && m_pyramid != NULL && m_pyramid.HasLegs(side))
         return false;

      if(d.kind == EXIT_OVERLAP)
      {
         eRecoveryExitCoordRequest cr = BeginTicketClose(dir, d.pairLast, d.pairFirst,
                                                          recovery_EXIT_REASON_LEGACY_OVERLAP,
                                                          ctx.now);
         if(cr == recovery_EXIT_BYPASS)
         {
            Log_Info("Strategy", "Overlap close: last " + (string)d.pairLast + " + first " + (string)d.pairFirst);
            m_exec.ClosePosition(d.pairLast);
            m_exec.ClosePosition(d.pairFirst);
            m_basket.Invalidate();
         }
         else if(cr == recovery_EXIT_BLOCKED)
            Log_Warn("Recovery", "exitblocked", "Overlap Core close blocked until Recovery reconciliation is safe");
      }
      else
      {
         eRecoveryExitCoordReason rr = d.kind == EXIT_TP ? recovery_EXIT_REASON_LEGACY_TP :
                                       d.kind == EXIT_SL ? recovery_EXIT_REASON_LEGACY_SL :
                                                           recovery_EXIT_REASON_LEGACY_TRAIL;
         eRecoveryExitCoordRequest cr = BeginFullSideClose(dir, rr, ctx.now);
         if(cr == recovery_EXIT_BYPASS)
         {
            string why = d.kind == EXIT_TP ? "virtual TP" : d.kind == EXIT_SL ? "virtual SL" : "virtual trailing";
            Log_Info("Strategy", "Basket close (" + why + ") dir=" + (string)dir + " positions=" + (string)side.count);
            m_exec.CloseBasket(side);
            m_basket.Invalidate();
         }
         else if(cr == recovery_EXIT_BLOCKED)
            Log_Warn("Recovery", "exitblocked", "Core basket exit blocked until Recovery reconciliation is safe");
      }
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

      SRecoveryT165GuardMetrics rg;
      bool recoveryHistoryOk = Recovery_T165ReadGuardMetrics(ctx.now, rg);
      double buyEconomic = Recovery_T165EconomicSideProfitPure(m_basket.buy.totalProfit,
                                                                rg.recoveryForBuyFloating);
      double sellEconomic = Recovery_T165EconomicSideProfitPure(m_basket.sell.totalProfit,
                                                                 rg.recoveryForSellFloating);
      double dayNet = m_basket.DayProfit() + buyEconomic + sellEconomic;
      double economicDayStartBalance = m_basket.DayStartBalance();
      bool dayNetValid = true;
      if(RecoveryMode_ == recovery_ACTIVE)
      {
         if(recoveryHistoryOk)
         {
            dayNet += rg.recoveryRealizedToday;
            economicDayStartBalance -= rg.recoveryRealizedToday;
         }
         else
         {
            dayNetValid = false;
            Log_WarnEvery("Guard", "t165dailyhistory",
                          "T16.5 không đọc được realized RecoveryMagic trong ngày; chỉ tạm hoãn DAILY guard, account/floating guards vẫn hoạt động",
                          Recovery_T165WaitLogSecondsPure(RecoveryWaitLogSeconds_));
         }
      }

      bool bothCoreOpen = m_basket.buy.count > 0 && m_basket.sell.count > 0;
      eGuardAction a = m_guard.CheckScoped(ctx.now,
                                           buyEconomic, sellEconomic,
                                           bothCoreOpen,
                                           dayNet, economicDayStartBalance,
                                           dayNetValid);
      if(a == GUARD_NONE) return false;

      bool coordinated = false;
      bool legacyMutation = false;
      bool buyEconomicOpen = m_basket.buy.count > 0 || rg.buyRecoveryOpen;
      bool sellEconomicOpen = m_basket.sell.count > 0 || rg.sellRecoveryOpen;

      if(a == GUARD_CLOSE_ACCOUNT)
      {
         if(RecoveryMode_ == recovery_ACTIVE && m_recoveryExit != NULL)
         {
            m_recoveryExit.BeginAccountWideClose(ctx.now);
            coordinated = true;
         }
         else
         {
            m_exec.CloseAllAccount();
            legacyMutation = true;
         }
      }
      else if(a == GUARD_CLOSE_BUY)
      {
         eRecoveryExitCoordRequest cr = BeginFullSideClose(BD_DIR_BUY,
                                                            recovery_EXIT_REASON_GUARD_SIDE,
                                                            ctx.now);
         if(cr == recovery_EXIT_BYPASS)
         {
            m_exec.CloseBasket(m_basket.buy);
            legacyMutation = true;
         }
         else coordinated = true;
      }
      else if(a == GUARD_CLOSE_SELL)
      {
         eRecoveryExitCoordRequest cr = BeginFullSideClose(BD_DIR_SELL,
                                                            recovery_EXIT_REASON_GUARD_SIDE,
                                                            ctx.now);
         if(cr == recovery_EXIT_BYPASS)
         {
            m_exec.CloseBasket(m_basket.sell);
            legacyMutation = true;
         }
         else coordinated = true;
      }
      else
      {
         eRecoveryExitCoordReason rr = a == GUARD_CLOSE_MAGIC_DAILY ?
                                       recovery_EXIT_REASON_GUARD_DAILY :
                                       recovery_EXIT_REASON_GUARD_MAGIC;
         if(buyEconomicOpen)
         {
            eRecoveryExitCoordRequest cr = BeginFullSideClose(BD_DIR_BUY, rr, ctx.now);
            if(cr == recovery_EXIT_BYPASS)
            {
               m_exec.CloseBasket(m_basket.buy);
               legacyMutation = true;
            }
            else coordinated = true;
         }
         if(sellEconomicOpen)
         {
            eRecoveryExitCoordRequest cr = BeginFullSideClose(BD_DIR_SELL, rr, ctx.now);
            if(cr == recovery_EXIT_BYPASS)
            {
               m_exec.CloseBasket(m_basket.sell);
               legacyMutation = true;
            }
            else coordinated = true;
         }
      }
      if(coordinated) DriveRecoveryExit(ctx.now);
      if(legacyMutation) m_basket.Invalidate();
      return true;
   }

public:
   void Init(CBasketManager *basket, CExecutionLayer *exec, ILotSizer *sizer,
             CMoneyGuard *guard, CDistancePlan *dist,
             CRecoveryEngine *recovery, CRecoveryExitCoordinator *recoveryExit,
             CCorePyramidEngine *pyramid)
   {
      m_basket       = basket;
      m_exec         = exec;
      m_sizer        = sizer;
      m_guard        = guard;
      m_dist         = dist;
      m_recovery     = recovery;
      m_recoveryExit = recoveryExit;
      m_pyramid      = pyramid;
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
         eRecoveryExitCoordRequest cr = BeginFullSideClose(BD_DIR_BUY,
                                                            recovery_EXIT_REASON_PANEL,
                                                            ctx.now);
         if(cr == recovery_EXIT_BYPASS)
         {
            m_exec.CloseBasket(m_basket.buy);
            m_basket.Invalidate();
         }
         else if(cr == recovery_EXIT_BLOCKED)
            Log_Warn("Recovery", "panelclose", "panel Close Buy blocked until Recovery reconciliation is safe");
         panelClose = true;
      }
      if(panelCloseSell && m_basket.sell.count > 0)
      {
         eRecoveryExitCoordRequest cr = BeginFullSideClose(BD_DIR_SELL,
                                                            recovery_EXIT_REASON_PANEL,
                                                            ctx.now);
         if(cr == recovery_EXIT_BYPASS)
         {
            m_exec.CloseBasket(m_basket.sell);
            m_basket.Invalidate();
         }
         else if(cr == recovery_EXIT_BLOCKED)
            Log_Warn("Recovery", "panelclose", "panel Close Sell blocked until Recovery reconciliation is safe");
         panelClose = true;
      }
      if(panelClose)
      {
         DriveRecoveryExit(ctx.now);
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

      if(m_recoveryExit != NULL && m_recoveryExit.HasBlockingWork())
      {
         DriveRecoveryExit(ctx.now);
         if(panelOpenBuy || panelOpenSell)
            Log_Warn("Recovery", "cleanupactive", "panel open ignored while Recovery exit cleanup/reconciliation is active");
         return;
      }

      if(m_recovery != NULL && RecoveryMode_ == recovery_ACTIVE && m_recovery.ActiveReady())
      {
         string recoveryWhy = "";
         if(m_recovery.DriveActive(*m_exec, ctx, recoveryWhy))
         {
            if(recoveryWhy != "")
               Log_WarnEvery("Recovery", "activedrive", "ACTIVE mutation chain: " + recoveryWhy,
                             Recovery_T165WaitLogSecondsPure(RecoveryWaitLogSeconds_));
            if(panelOpenBuy || panelOpenSell)
               Log_Warn("Recovery", "activewins", "panel open ignored because an ACTIVE Recovery mutation is in flight");
            return;
         }
      }

      bool exitBuy  = ApplyExit(ctx, m_basket.buy,  BD_DIR_BUY);
      bool exitSell = ApplyExit(ctx, m_basket.sell, BD_DIR_SELL);
      if(exitBuy || exitSell)
      {
         DriveRecoveryExit(ctx.now);
         if(panelOpenBuy || panelOpenSell)
            Log_Warn("Recovery", "basketclose", "panel open ignored because a basket exit fired");
         return;
      }

      bool panelMutation = false;
      if(panelOpenBuy)
      {
         if(m_exec.BusyOpen(BD_DIR_BUY)) Log_Warn("Strategy", "panelbusy", "panel Open Buy ignored: async open in flight");
         else if(m_exec.OpenMarket(BD_DIR_BUY, Cfg.EditLot, m_basket.buy.count + 1))
         { m_basket.Invalidate(); panelMutation = true; }
      }
      if(panelOpenSell)
      {
         if(m_exec.BusyOpen(BD_DIR_SELL)) Log_Warn("Strategy", "panelbusy", "panel Open Sell ignored: async open in flight");
         else if(m_exec.OpenMarket(BD_DIR_SELL, Cfg.EditLot, m_basket.sell.count + 1))
         { m_basket.Invalidate(); panelMutation = true; }
      }
      if(panelMutation) return;

      // T17 priority: high-scope Guard/Recovery/Exit trước; sau đó Pyramid.
      // Entry filters chỉ cấp quyền ADD; LIFO Peel giảm rủi ro vẫn được Drive
      // đánh giá ngay cả khi news/time/halt/ADX/spread đang chặn risk mới.
      if(m_pyramid != NULL)
      {
         string pyrWhy = "";
         bool allowPyramidAddBuy = m_newSeriesFilters.Allow(ctx, BD_DIR_BUY);
         if(m_basket.buy.count > 0 &&
            m_pyramid.Drive(ctx, m_basket.buy, BD_DIR_BUY, MaxOrdersBuy,
                            m_recovery, allowPyramidAddBuy, pyrWhy))
         {
            if(pyrWhy != "") Log_Info("Pyramid", pyrWhy);
            m_basket.Invalidate();
            return;
         }
         pyrWhy = "";
         bool allowPyramidAddSell = m_newSeriesFilters.Allow(ctx, BD_DIR_SELL);
         if(m_basket.sell.count > 0 &&
            m_pyramid.Drive(ctx, m_basket.sell, BD_DIR_SELL, MaxOrdersSell,
                            m_recovery, allowPyramidAddSell, pyrWhy))
         {
            if(pyrWhy != "") Log_Info("Pyramid", pyrWhy);
            m_basket.Invalidate();
            return;
         }
      }

      TryOpenSeries(ctx);
      if(Hedge_AllowsGridAdd(m_basket.buy.count))  TryGridAdd(ctx, m_basket.buy,  BD_DIR_BUY,  MaxOrdersBuy);
      if(Hedge_AllowsGridAdd(m_basket.sell.count)) TryGridAdd(ctx, m_basket.sell, BD_DIR_SELL, MaxOrdersSell);

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