//+------------------------------------------------------------------+
//| Strategy.mqh — BlackDragon T17.4 runtime                         |
//| P0 floating MoneyGuard + Pyramid/DCA coexistence + re-arm.       |
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
   eGuardAction       m_guardLatched;
   datetime           m_guardLatchAt;

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

   void RefreshPyramidCampaigns(const EAContext &ctx)
   {
      if(m_pyramid == NULL) return;
      bool buyOk = m_pyramid.RefreshCampaignStats(m_basket.buy, BD_DIR_BUY, ctx.now);
      bool sellOk = m_pyramid.RefreshCampaignStats(m_basket.sell, BD_DIR_SELL, ctx.now);
      if(!buyOk || !sellOk)
         Log_WarnEvery("Pyramid", "campaignhistory",
                       "T17.4 chưa đọc đủ Pyramid campaign history; tạm hoãn Pyramid ADD/economic basket TP/PctDiff, risk-reducing Peel và absolute floating MoneyGuard vẫn hoạt động",
                       Recovery_T165WaitLogSecondsPure(RecoveryWaitLogSeconds_));
   }

   string GuardActionName(const eGuardAction action) const
   {
      if(action == GUARD_CLOSE_ACCOUNT) return "ACCOUNT";
      if(action == GUARD_CLOSE_MAGIC) return "MAGIC";
      if(action == GUARD_CLOSE_BUY) return "BUY";
      if(action == GUARD_CLOSE_SELL) return "SELL";
      if(action == GUARD_CLOSE_MAGIC_DAILY) return "DAILY";
      return "NONE";
   }

   bool GuardScopeFlat(const eGuardAction action,
                       const SRecoveryT165GuardMetrics &rg) const
   {
      if(action == GUARD_CLOSE_ACCOUNT)
         return PositionsTotal() == 0;
      if(action == GUARD_CLOSE_BUY)
         return m_basket.buy.count == 0 && !rg.buyRecoveryOpen;
      if(action == GUARD_CLOSE_SELL)
         return m_basket.sell.count == 0 && !rg.sellRecoveryOpen;
      if(action == GUARD_CLOSE_MAGIC || action == GUARD_CLOSE_MAGIC_DAILY)
         return m_basket.buy.count == 0 && m_basket.sell.count == 0 &&
                !rg.buyRecoveryOpen && !rg.sellRecoveryOpen;
      return true;
   }

   bool AnyOpenPending() const
   {
      if(m_exec == NULL) return false;
      if(m_exec.BusyOpen(BD_DIR_BUY) || m_exec.BusyOpen(BD_DIR_SELL)) return true;
      if(m_pyramid != NULL &&
         (m_pyramid.HasPending(BD_DIR_BUY) || m_pyramid.HasPending(BD_DIR_SELL)))
         return true;
      return false;
   }

   void LatchGuard(const eGuardAction action, const datetime now)
   {
      if(action == GUARD_NONE) return;
      eGuardAction next = MG_LatchNextPure(m_guardLatched, action, false);
      if(m_guardLatched == GUARD_NONE && next != GUARD_NONE)
      {
         m_guardLatchAt = now;
         Log_Warn("Guard", "latch", "T17.4 MoneyGuard CLOSE LATCHED scope=" +
                  GuardActionName(next) + "; no new Seed/DCA/Pyramid/Recovery ADD until flat");
      }
      m_guardLatched = next;
   }

   bool DriveGuardLatch(const EAContext &ctx,
                        const SRecoveryT165GuardMetrics &rg)
   {
      if(m_guardLatched == GUARD_NONE) return false;

      bool flat = GuardScopeFlat(m_guardLatched, rg);
      bool pendingOpen = AnyOpenPending();
      bool pendingClose = m_exec != NULL && m_exec.HasAnyPendingClose();
      bool recoveryBusy = RecoveryMode_ == recovery_ACTIVE && m_recoveryExit != NULL &&
                          m_recoveryExit.HasBlockingWork();

      if(flat && !pendingOpen && !pendingClose && !recoveryBusy)
      {
         Log_Info("Guard", "T17.4 MoneyGuard close-to-flat COMPLETE scope=" +
                  GuardActionName(m_guardLatched) + " latchedAt=" +
                  TimeToString(m_guardLatchAt, TIME_DATE | TIME_SECONDS));
         m_guardLatched = MG_LatchNextPure(m_guardLatched, GUARD_NONE, true);
         m_guardLatchAt = 0;
         return true; // do not reopen on the same tick that flatten completes
      }

      // Existing open outcome must be known before issuing contradictory close.
      if(pendingOpen)
      {
         Log_WarnEvery("Guard", "waitopen", "MoneyGuard latch waiting for in-flight OPEN outcome before close-to-flat",
                       Recovery_T165WaitLogSecondsPure(RecoveryWaitLogSeconds_));
         return true;
      }
      if(pendingClose)
         return true;
      if(recoveryBusy)
      {
         DriveRecoveryExit(ctx.now);
         return true;
      }

      bool coordinated = false;
      bool legacyMutation = false;
      bool buyOpen = m_basket.buy.count > 0 || rg.buyRecoveryOpen;
      bool sellOpen = m_basket.sell.count > 0 || rg.sellRecoveryOpen;

      if(m_guardLatched == GUARD_CLOSE_ACCOUNT)
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
      else if(m_guardLatched == GUARD_CLOSE_BUY)
      {
         eRecoveryExitCoordRequest cr = BeginFullSideClose(BD_DIR_BUY,
                                                            recovery_EXIT_REASON_GUARD_SIDE,
                                                            ctx.now);
         if(cr == recovery_EXIT_BYPASS)
         {
            m_exec.CloseBasket(m_basket.buy);
            legacyMutation = true;
         }
         else if(cr == recovery_EXIT_BLOCKED)
            Log_Warn("Guard", "latchbuy", "MoneyGuard BUY latch waiting for Recovery reconciliation");
         else coordinated = true;
      }
      else if(m_guardLatched == GUARD_CLOSE_SELL)
      {
         eRecoveryExitCoordRequest cr = BeginFullSideClose(BD_DIR_SELL,
                                                            recovery_EXIT_REASON_GUARD_SIDE,
                                                            ctx.now);
         if(cr == recovery_EXIT_BYPASS)
         {
            m_exec.CloseBasket(m_basket.sell);
            legacyMutation = true;
         }
         else if(cr == recovery_EXIT_BLOCKED)
            Log_Warn("Guard", "latchsell", "MoneyGuard SELL latch waiting for Recovery reconciliation");
         else coordinated = true;
      }
      else
      {
         eRecoveryExitCoordReason rr = m_guardLatched == GUARD_CLOSE_MAGIC_DAILY ?
                                       recovery_EXIT_REASON_GUARD_DAILY :
                                       recovery_EXIT_REASON_GUARD_MAGIC;
         if(buyOpen)
         {
            eRecoveryExitCoordRequest cr = BeginFullSideClose(BD_DIR_BUY, rr, ctx.now);
            if(cr == recovery_EXIT_BYPASS)
            {
               m_exec.CloseBasket(m_basket.buy);
               legacyMutation = true;
            }
            else if(cr == recovery_EXIT_BLOCKED)
               Log_Warn("Guard", "latchmagicbuy", "MoneyGuard MAGIC latch BUY side waiting for Recovery reconciliation");
            else coordinated = true;
         }
         if(sellOpen)
         {
            eRecoveryExitCoordRequest cr = BeginFullSideClose(BD_DIR_SELL, rr, ctx.now);
            if(cr == recovery_EXIT_BYPASS)
            {
               m_exec.CloseBasket(m_basket.sell);
               legacyMutation = true;
            }
            else if(cr == recovery_EXIT_BLOCKED)
               Log_Warn("Guard", "latchmagicsell", "MoneyGuard MAGIC latch SELL side waiting for Recovery reconciliation");
            else coordinated = true;
         }
      }
      if(coordinated) DriveRecoveryExit(ctx.now);
      if(legacyMutation) m_basket.Invalidate();
      return true;
   }

   double PctDiffExecutionBufferCash(const EAContext &ctx) const
   {
      if(PctDiffClose <= 0.0) return 0.0;
      double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      if(tickSize <= 0.0 || tickValue <= 0.0) return DBL_MAX;

      double lots = m_basket.buy.totalLots + m_basket.sell.totalLots;
      int closeRequests = m_basket.buy.count + m_basket.sell.count;
      if(RecoveryMode_ == recovery_ACTIVE && RecoveryMagic_ > 0)
      {
         for(int i = PositionsTotal() - 1; i >= 0; i--)
         {
            ulong ticket = PositionGetTicket(i);
            if(ticket == 0) continue;
            if(PositionGetString(POSITION_SYMBOL) != _Symbol ||
               PositionGetInteger(POSITION_MAGIC) != (long)RecoveryMagic_)
               continue;
            lots += PositionGetDouble(POSITION_VOLUME);
            closeRequests++;
         }
      }
      if(lots <= 0.0) return 0.0;
      double spreadPrice = MathMax(ctx.ask - ctx.bid, 0.0);
      double deviationPrice = (double)Exec_Deviation(Slippage_, Cfg.PointScale) * ctx.point;
      return MG_PctDiffExecutionReserveCashPure(spreadPrice,
                                                deviationPrice,
                                                lots,
                                                closeRequests,
                                                tickSize,
                                                tickValue);
   }

   bool ApplyGuardPriority(const EAContext &ctx)
   {
      if(m_guard == NULL) return false;
      SRecoveryT165GuardMetrics rg;
      Recovery_T165ReadGuardMetrics(ctx.now, rg); // floating is valid even if day-history seed fails

      if(m_guardLatched != GUARD_NONE)
         return DriveGuardLatch(ctx, rg);

      double buyFloating = m_basket.buy.totalProfit + rg.recoveryForBuyFloating;
      double sellFloating = m_basket.sell.totalProfit + rg.recoveryForSellFloating;
      bool bothCoreOpen = m_basket.buy.count > 0 && m_basket.sell.count > 0;
      double accountFloating = AccountInfoDouble(ACCOUNT_PROFIT);

      eGuardAction action = m_guard.CheckFloatingPriority(ctx.now,
                                                          buyFloating,
                                                          sellFloating,
                                                          bothCoreOpen,
                                                          accountFloating);
      if(action == GUARD_NONE) return false;
      LatchGuard(action, ctx.now);
      return DriveGuardLatch(ctx, rg);
   }

   bool ApplyGuardSecondary(const EAContext &ctx)
   {
      if(m_guard == NULL) return false;
      SRecoveryT165GuardMetrics rg;
      bool recoveryHistoryOk = Recovery_T165ReadGuardMetrics(ctx.now, rg);
      if(m_guardLatched != GUARD_NONE)
         return DriveGuardLatch(ctx, rg);

      double buyFloating = m_basket.buy.totalProfit + rg.recoveryForBuyFloating;
      double sellFloating = m_basket.sell.totalProfit + rg.recoveryForSellFloating;
      double dayNet = m_basket.DayProfit() + buyFloating + sellFloating;
      double dayStartBalance = m_basket.DayStartBalance();
      bool dayNetValid = true;
      if(RecoveryMode_ == recovery_ACTIVE)
      {
         if(recoveryHistoryOk)
         {
            dayNet += rg.recoveryRealizedToday;
            dayStartBalance -= rg.recoveryRealizedToday;
         }
         else
         {
            dayNetValid = false;
            Log_WarnEvery("Guard", "t165dailyhistory",
                          "T16.5 không đọc được realized RecoveryMagic trong ngày; chỉ tạm hoãn DAILY guard, absolute floating-money guards vẫn hoạt động",
                          Recovery_T165WaitLogSecondsPure(RecoveryWaitLogSeconds_));
         }
      }

      bool bothCoreOpen = m_basket.buy.count > 0 && m_basket.sell.count > 0;
      double pctBuffer = PctDiffExecutionBufferCash(ctx);
      double pyramidCampaignRealized = 0.0;
      bool pctCampaignHistoryValid = true;
      if(CorePyramidMode_ != pyramid_TAT && m_pyramid != NULL && bothCoreOpen)
      {
         pctCampaignHistoryValid = m_pyramid.CampaignHistoryReady(BD_DIR_BUY) &&
                                   m_pyramid.CampaignHistoryReady(BD_DIR_SELL);
         if(pctCampaignHistoryValid)
            pyramidCampaignRealized = m_pyramid.CampaignRealized(BD_DIR_BUY) +
                                      m_pyramid.CampaignRealized(BD_DIR_SELL);
         else if(PctDiffClose > 0.0)
            Log_WarnEvery("Guard", "t174pcthistory",
                          "T17.4 PctDiff deferred: active Pyramid campaign history is not ready",
                          Recovery_T165WaitLogSecondsPure(RecoveryWaitLogSeconds_));
      }
      eGuardAction action = m_guard.CheckSecondaryFloating(ctx.now,
                                                           buyFloating,
                                                           sellFloating,
                                                           bothCoreOpen,
                                                           dayNet,
                                                           dayStartBalance,
                                                           dayNetValid,
                                                           pyramidCampaignRealized,
                                                           pctCampaignHistoryValid,
                                                           pctBuffer);
      if(action == GUARD_NONE) return false;
      LatchGuard(action, ctx.now);
      return DriveGuardLatch(ctx, rg);
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

   bool TryGridAdd(const EAContext &ctx, BasketSide &side,
                   const int dir, const int maxOrders)
   {
      if(side.count <= 0 || maxOrders <= 0) return false;

      // T17.4: DCA evaluates only Seed+DCA positions even while Pyramid is live.
      BasketSide dcaSide;
      if(m_pyramid != NULL) m_pyramid.BuildDcaView(side, dcaSide);
      else dcaSide = side;
      if(dcaSide.count <= 0 || dcaSide.count >= maxOrders) return false;

      datetime lastBar = (dir == BD_DIR_BUY) ? m_basket.LastBuyBar() : m_basket.LastSellBar();
      if(lastBar == ctx.barTime) return false;
      if(m_exec.BusyOpen(dir)) return false;
      if(!m_gridFilters.Allow(ctx, dir)) return false;
      PositionInfo last = dcaSide.pos[dcaSide.count - 1];

      datetime lastCoreAdd = last.openTime;
      if(m_pyramid != NULL)
      {
         datetime pyrTime = m_pyramid.LatestCoreAddTime(side, dir);
         if(pyrTime > lastCoreAdd) lastCoreAdd = pyrTime;
      }
      if(MinuteStop > 0 && lastCoreAdd > 0 &&
         ctx.now <= lastCoreAdd + MinuteStop * 60) return false;

      int dist = m_dist.DistancePoints(dcaSide.count) * Cfg.PointScale;
      bool hit = (dir == BD_DIR_BUY)
         ? (ctx.ask <= last.openPrice - dist * ctx.point)
         : (ctx.bid >= last.openPrice + dist * ctx.point);
      if(!hit) return false;

      double nextLot = m_sizer.NextLot(dcaSide);
      if(RecoveryMode_ == recovery_ACTIVE && RecoveryDcaMarginReserve_)
      {
         string reserveWhy = "";
         double requiredMargin = 0.0;
         double projectedHedgeLot = 0.0;
         bool futureGenerationAllowed = m_recovery != NULL &&
            m_recovery.T16CanOpenFurtherGeneration(RecoveryDir(dir));

         // Count must stay Seed+DCA for Recovery reachability, while economic
         // Core lots include live Pyramid for projected Hedge margin.
         dcaSide.totalLots = side.totalLots;
         if(!Recovery_T165ProjectedDcaReserveAllows(dir, dcaSide, nextLot,
                                                    futureGenerationAllowed,
                                                    reserveWhy,
                                                    requiredMargin,
                                                    projectedHedgeLot))
         {
            Log_WarnEvery("Recovery", "t165dcareserve" + (string)dir,
                          reserveWhy,
                          Recovery_T165WaitLogSecondsPure(RecoveryWaitLogSeconds_));
            return false;
         }
      }

      // No proactive reserve when PyramidReserveDcaSlots_=0, but if Pyramid
      // consumed the final slot, a due DCA gets priority by releasing newest P.
      if(side.count >= maxOrders)
      {
         if(m_pyramid != NULL && m_pyramid.HasLegs(side))
         {
            string releaseWhy = "";
            if(m_pyramid.ReleaseNewestForDca(side, dir, releaseWhy))
            {
               if(releaseWhy != "") Log_Warn("Pyramid", "dcapriority", releaseWhy);
               m_basket.Invalidate();
               return true;
            }
         }
         return false;
      }

      if(m_exec.OpenMarket(dir, nextLot, dcaSide.count + 1))
      {
         m_basket.Invalidate();
         return true;
      }
      return false;
   }

   bool ApplyExit(const EAContext &ctx, BasketSide &side, const int dir)
   {
      ExitDecision d = m_exitPolicy.Check(ctx, side, dir);
      if(d.kind == EXIT_NONE) return false;

      if(d.kind == EXIT_TP && m_pyramid != NULL)
      {
         double economicTp = side.tpLevel;
         if(!m_pyramid.EconomicTpLevel(side, dir, side.tpLevel, economicTp))
            return false;
         bool isBuy = (dir == BD_DIR_BUY);
         if(!Exit_VirtualTpHit(isBuy, economicTp, ctx.bid, ctx.ask))
            return false;
      }

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

      if(TP_Mode == mode_Real && Cfg.TP != 0 && m_pyramid != NULL)
      {
         double economicTp = tp;
         int dir = isBuy ? BD_DIR_BUY : BD_DIR_SELL;
         if(m_pyramid.EconomicTpLevel(side, dir, tp, economicTp))
            tp = NormalizeDouble(economicTp, ctx.digits);
         else
            tp = 0.0;
      }

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

public:
   void Init(CBasketManager *basket, CExecutionLayer *exec, ILotSizer *sizer,
             CMoneyGuard *guard, CDistancePlan *dist,
             CRecoveryEngine *recovery, CRecoveryExitCoordinator *recoveryExit,
             CCorePyramidEngine *pyramid)
   {
      m_basket       = basket;
      m_exec         = exec;
      m_sizer        = sizer;
      m_guard         = guard;
      m_dist         = dist;
      m_recovery     = recovery;
      m_recoveryExit = recoveryExit;
      m_pyramid      = pyramid;
      m_guardLatched = GUARD_NONE;
      m_guardLatchAt = 0;
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

      // Explicit owner close remains allowed to short-circuit everything.
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

      // P0: absolute floating-money guard is evaluated BEFORE any pending-open
      // short-circuit, Recovery mutation, Pyramid mutation, Seed or DCA.
      if(ApplyGuardPriority(ctx))
      {
         if(panelOpenBuy || panelOpenSell)
            Log_Warn("Strategy", "guardclose", "panel open ignored because MoneyGuard close latch owns Strategy");
         return;
      }

      if(m_pyramid != NULL &&
         (m_pyramid.HasPending(BD_DIR_BUY) || m_pyramid.HasPending(BD_DIR_SELL)))
      {
         Log_WarnEvery("Pyramid", "strictpending",
                       "T17 strict Pyramid mutation đang chờ broker/reconcile; tạm khóa mutation Strategy cho tới khi xác định outcome",
                       Recovery_T165WaitLogSecondsPure(RecoveryWaitLogSeconds_));
         return;
      }

      if(m_exec.HasAnyPendingClose())
      {
         if(panelOpenBuy || panelOpenSell)
            Log_Warn("Strategy", "pendingclose", "panel open ignored while an async close is pending");
         return;
      }

      RefreshPyramidCampaigns(ctx);

      // Daily/PctDiff are secondary to absolute-money guards but still precede
      // Recovery/legacy exits and all new risk mutations.
      if(ApplyGuardSecondary(ctx))
      {
         if(panelOpenBuy || panelOpenSell)
            Log_Warn("Strategy", "guardsecondary", "panel open ignored because secondary MoneyGuard close latch owns Strategy");
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

      // Pyramid risk exit/add is evaluated before adverse DCA. ADD cannot hit
      // on the same adverse geometry; Peel remains urgent and may win the tick.
      if(m_pyramid != NULL)
      {
         string pyrWhy = "";
         datetime buyLastBar = m_basket.LastBuyBar();
         bool allowPyramidAddBuy = m_newSeriesFilters.Allow(ctx, BD_DIR_BUY);
         if(m_basket.buy.count > 0)
         {
            bool changed = m_pyramid.Drive(ctx, m_basket.buy, BD_DIR_BUY, MaxOrdersBuy,
                                           m_recovery, allowPyramidAddBuy,
                                           buyLastBar, pyrWhy);
            if(changed)
            {
               if(pyrWhy != "") Log_Info("Pyramid", pyrWhy);
               m_basket.Invalidate();
               return;
            }
            if(pyrWhy != "")
               Log_WarnEvery("Pyramid", "t174block0", pyrWhy,
                             Recovery_T165WaitLogSecondsPure(RecoveryWaitLogSeconds_));
         }

         pyrWhy = "";
         datetime sellLastBar = m_basket.LastSellBar();
         bool allowPyramidAddSell = m_newSeriesFilters.Allow(ctx, BD_DIR_SELL);
         if(m_basket.sell.count > 0)
         {
            bool changed = m_pyramid.Drive(ctx, m_basket.sell, BD_DIR_SELL, MaxOrdersSell,
                                           m_recovery, allowPyramidAddSell,
                                           sellLastBar, pyrWhy);
            if(changed)
            {
               if(pyrWhy != "") Log_Info("Pyramid", pyrWhy);
               m_basket.Invalidate();
               return;
            }
            if(pyrWhy != "")
               Log_WarnEvery("Pyramid", "t174block1", pyrWhy,
                             Recovery_T165WaitLogSecondsPure(RecoveryWaitLogSeconds_));
         }
      }

      TryOpenSeries(ctx);
      if(Hedge_AllowsGridAdd(m_basket.buy.count) &&
         TryGridAdd(ctx, m_basket.buy, BD_DIR_BUY, MaxOrdersBuy)) return;
      if(Hedge_AllowsGridAdd(m_basket.sell.count) &&
         TryGridAdd(ctx, m_basket.sell, BD_DIR_SELL, MaxOrdersSell)) return;

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
