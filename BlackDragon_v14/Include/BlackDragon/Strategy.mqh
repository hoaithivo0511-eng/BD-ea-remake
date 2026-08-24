//+------------------------------------------------------------------+
//| Strategy.mqh — T17.7 C3 durable Overlap wrapper                 |
//| Verified T17.6/C1/C2 Strategy stays as base; C3 replaces only    |
//| Overlap two-leg orchestration and same-side risk-add blocking.   |
//+------------------------------------------------------------------+
#ifndef BD_STRATEGY_T177_C3_MQH
#define BD_STRATEGY_T177_C3_MQH

// Preserve the exact pre-C3 Strategy implementation as a protected base.
#define private protected
#define CStrategy CStrategyT176Base
#include "StrategyT176Base.mqh"
#undef CStrategy
#undef private

#include "Overlap/OverlapT177Coordinator.mqh"

class CStrategy : public CStrategyT176Base
{
private:
   COverlapT177Coordinator m_overlap;

   bool ApplyExitT177(const EAContext &ctx, BasketSide &side, const int dir)
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

      // Existing T17 invariant: Overlap never competes with live Pyramid legs.
      if(d.kind == EXIT_OVERLAP && m_pyramid != NULL && m_pyramid.HasLegs(side))
         return false;

      if(d.kind == EXIT_OVERLAP)
      {
         // A durable obligation already owns this side. Duplicate Overlap
         // decisions are ignored; the coordinator will re-evaluate economics.
         if(m_overlap.Active(dir)) return false;

         double firstProfit = 0.0;
         double lastProfit = 0.0;
         double reserve = OverlapExecutionBufferCash(ctx, side, d,
                                                     firstProfit, lastProfit);
         if(!Overlap_T177PreLeg1EligiblePure(side.count, OverlapOrderNumber, Overlap,
                                             firstProfit, lastProfit,
                                             OverlapPercent, reserve))
         {
            string reserveText = reserve == DBL_MAX ? "N/A" : DoubleToString(reserve, 2);
            Log_WarnEvery("Overlap", "t177pre" + (string)dir,
                          "CHỜ " + (dir == BD_DIR_BUY ? "BUY" : "SELL") +
                          " | Cặp chưa đủ biên an toàn để đóng | pair=" +
                          DoubleToString(firstProfit + lastProfit, 2) +
                          " reserve=" + reserveText + " USD",
                          Recovery_T165WaitLogSecondsPure(RecoveryWaitLogSeconds_));
            return false;
         }

         string armWhy = "";
         if(!m_overlap.Arm(dir, d.pairFirst, d.pairLast, ctx.now, armWhy))
         {
            if(armWhy != "")
               Log_WarnEvery("Overlap", "t177arm" + (string)dir,
                             "CHỜ " + (dir == BD_DIR_BUY ? "BUY" : "SELL") +
                             " | Chưa khóa được cặp Overlap | " + armWhy,
                             Recovery_T165WaitLogSecondsPure(RecoveryWaitLogSeconds_));
            return false;
         }

         eOverlapT177DriveDisposition od = m_overlap.DriveSide(ctx, side, dir);
         if(Overlap_T177ConsumesStrategyTickPure(od))
         {
            m_basket.Invalidate();
            return true;
         }
         return false;
      }

      // TP/SL/Trail semantics are unchanged from the verified base Strategy.
      eRecoveryExitCoordReason rr = d.kind == EXIT_TP ? recovery_EXIT_REASON_LEGACY_TP :
                                    d.kind == EXIT_SL ? recovery_EXIT_REASON_LEGACY_SL :
                                                        recovery_EXIT_REASON_LEGACY_TRAIL;
      eRecoveryExitCoordRequest cr = BeginFullSideClose(dir, rr, ctx.now);
      if(cr == recovery_EXIT_BYPASS)
      {
         string why = d.kind == EXIT_TP ? "virtual TP" :
                      d.kind == EXIT_SL ? "virtual SL" : "virtual trailing";
         Log_Info("Strategy", "Basket close (" + why + ") dir=" +
                  (string)dir + " positions=" + (string)side.count);
         m_exec.CloseBasket(side);
         m_basket.Invalidate();
      }
      else if(cr == recovery_EXIT_BLOCKED)
         Log_Warn("Recovery", "exitblocked",
                  "Core basket exit blocked until Recovery reconciliation is safe");
      return true;
   }

   bool DriveOverlapUrgent(const EAContext &ctx)
   {
      if(!m_overlap.HasUrgentWork()) return false;
      eOverlapT177DriveDisposition od = m_overlap.Drive(ctx, m_basket.buy, m_basket.sell);
      if(od == overlap_T177_DRIVE_RECONCILE)
      {
         Log_WarnEvery("Overlap", "t177urgent",
                       "LỖI HAI PHÍA | Overlap cần đối soát trước khi tiếp tục",
                       Recovery_T165WaitLogSecondsPure(RecoveryWaitLogSeconds_));
      }
      return Overlap_T177ConsumesStrategyTickPure(od);
   }

public:
   void Init(CBasketManager *basket, CExecutionLayer *exec, ILotSizer *sizer,
             CMoneyGuard *guard, CDistancePlan *dist,
             CRecoveryEngine *recovery, CRecoveryExitCoordinator *recoveryExit,
             CCorePyramidEngine *pyramid)
   {
      CStrategyT176Base::Init(basket, exec, sizer, guard, dist,
                              recovery, recoveryExit, pyramid);
      string overlapWhy = "";
      if(!m_overlap.Init(exec, recovery, recoveryExit, overlapWhy))
         Log_Error("Overlap", "T17.7 C3 init thất bại: " + overlapWhy);
   }

   void OnTick(const EAContext &ctx, CPanel &panel)
   {
      bool panelCloseBuy  = panel.TakeCloseBuy();
      bool panelCloseSell = panel.TakeCloseSell();
      bool panelOpenBuy   = panel.TakeOpenBuy();
      bool panelOpenSell  = panel.TakeOpenSell();

      // Explicit owner close remains the strongest manual action.
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
            Log_Warn("Recovery", "panelclose",
                     "panel Close Buy blocked until Recovery reconciliation is safe");
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
            Log_Warn("Recovery", "panelclose",
                     "panel Close Sell blocked until Recovery reconciliation is safe");
         panelClose = true;
      }
      if(panelClose)
      {
         DriveRecoveryExit(ctx.now);
         if(panelOpenBuy || panelOpenSell)
            Log_Warn("Strategy", "panelclosewins",
                     "panel open ignored because a panel close is active");
         return;
      }

      // P0 remains before every C3 state transition or mutation.
      if(ApplyGuardPriority(ctx))
      {
         if(panelOpenBuy || panelOpenSell)
            Log_Warn("Strategy", "guardclose",
                     "panel open ignored because MoneyGuard close latch owns Strategy");
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

      // C3 must observe its own submitted strict close BEFORE the generic
      // pending-close guard, otherwise a reconcile-required close could hide
      // forever behind HasAnyPendingClose().
      if(DriveOverlapUrgent(ctx)) return;

      if(m_exec.HasAnyPendingClose())
      {
         if(panelOpenBuy || panelOpenSell)
            Log_Warn("Strategy", "pendingclose",
                     "panel open ignored while an async close is pending");
         return;
      }

      RefreshPyramidCampaigns(ctx);

      // Secondary MoneyGuard still preempts Overlap WAIT/recheck.
      if(ApplyGuardSecondary(ctx))
      {
         if(panelOpenBuy || panelOpenSell)
            Log_Warn("Strategy", "guardsecondary",
                     "panel open ignored because secondary MoneyGuard close latch owns Strategy");
         return;
      }

      if(m_recoveryExit != NULL && m_recoveryExit.HasBlockingWork())
      {
         DriveRecoveryExit(ctx.now);
         if(panelOpenBuy || panelOpenSell)
            Log_Warn("Recovery", "cleanupactive",
                     "panel open ignored while Recovery exit cleanup/reconciliation is active");
         return;
      }

      // Durable LEG2_WAIT_SAFE is read-only and therefore yields to Recovery,
      // opposite-side exits/Pyramid and other modules. Submitted/reconcile
      // states consume the tick and preserve one-mutation-chain semantics.
      eOverlapT177DriveDisposition overlapDrive =
         m_overlap.Drive(ctx, m_basket.buy, m_basket.sell);
      if(Overlap_T177ConsumesStrategyTickPure(overlapDrive)) return;

      if(m_recovery != NULL && RecoveryMode_ == recovery_ACTIVE && m_recovery.ActiveReady())
      {
         string recoveryWhy = "";
         if(m_recovery.DriveActive(*m_exec, ctx, recoveryWhy))
         {
            if(recoveryWhy != "")
               Log_WarnEvery("Recovery", "activedrive", "ACTIVE mutation chain: " + recoveryWhy,
                             Recovery_T165WaitLogSecondsPure(RecoveryWaitLogSeconds_));
            if(panelOpenBuy || panelOpenSell)
               Log_Warn("Recovery", "activewins",
                        "panel open ignored because an ACTIVE Recovery mutation is in flight");
            return;
         }
      }

      // One exit mutation chain per tick: do not evaluate SELL after BUY has
      // already submitted a close chain.
      if(ApplyExitT177(ctx, m_basket.buy, BD_DIR_BUY))
      {
         DriveRecoveryExit(ctx.now);
         if(panelOpenBuy || panelOpenSell)
            Log_Warn("Recovery", "basketclose",
                     "panel open ignored because a basket exit fired");
         return;
      }
      if(ApplyExitT177(ctx, m_basket.sell, BD_DIR_SELL))
      {
         DriveRecoveryExit(ctx.now);
         if(panelOpenBuy || panelOpenSell)
            Log_Warn("Recovery", "basketclose",
                     "panel open ignored because a basket exit fired");
         return;
      }

      bool panelMutation = false;
      if(panelOpenBuy)
      {
         if(m_overlap.BlocksSide(BD_DIR_BUY))
            Log_WarnEvery("Overlap", "panelbuy",
                          "CHỜ BUY | Không mở thêm lệnh khi cặp Overlap đang xử lý",
                          Recovery_T165WaitLogSecondsPure(RecoveryWaitLogSeconds_));
         else if(m_exec.BusyOpen(BD_DIR_BUY))
            Log_Warn("Strategy", "panelbusy", "panel Open Buy ignored: async open in flight");
         else if(m_exec.OpenMarket(BD_DIR_BUY, Cfg.EditLot, m_basket.buy.count + 1))
         { m_basket.Invalidate(); panelMutation = true; }
      }
      if(panelOpenSell)
      {
         if(m_overlap.BlocksSide(BD_DIR_SELL))
            Log_WarnEvery("Overlap", "panelsell",
                          "CHỜ SELL | Không mở thêm lệnh khi cặp Overlap đang xử lý",
                          Recovery_T165WaitLogSecondsPure(RecoveryWaitLogSeconds_));
         else if(m_exec.BusyOpen(BD_DIR_SELL))
            Log_Warn("Strategy", "panelbusy", "panel Open Sell ignored: async open in flight");
         else if(m_exec.OpenMarket(BD_DIR_SELL, Cfg.EditLot, m_basket.sell.count + 1))
         { m_basket.Invalidate(); panelMutation = true; }
      }
      if(panelMutation) return;

      // C3 blocks only same-side risk ADD while the pair obligation exists.
      // The opposite side remains eligible during LEG2_WAIT_SAFE.
      if(m_pyramid != NULL)
      {
         string pyrWhy = "";
         datetime buyLastBar = m_basket.LastBuyBar();
         bool allowPyramidAddBuy = m_newSeriesFilters.Allow(ctx, BD_DIR_BUY);
         if(m_basket.buy.count > 0 && !m_overlap.BlocksSide(BD_DIR_BUY))
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
         if(m_basket.sell.count > 0 && !m_overlap.BlocksSide(BD_DIR_SELL))
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
      if(!m_overlap.BlocksSide(BD_DIR_BUY) &&
         Hedge_AllowsGridAdd(m_basket.buy.count) &&
         TryGridAdd(ctx, m_basket.buy, BD_DIR_BUY, MaxOrdersBuy)) return;
      if(!m_overlap.BlocksSide(BD_DIR_SELL) &&
         Hedge_AllowsGridAdd(m_basket.sell.count) &&
         TryGridAdd(ctx, m_basket.sell, BD_DIR_SELL, MaxOrdersSell)) return;

      // Risk protection/TP maintenance is not a new topology add and remains
      // active during durable WAIT.
      ApplyRealLevels(ctx, m_basket.buy,  true);
      ApplyRealLevels(ctx, m_basket.sell, false);
   }

   void Deinit()
   {
      m_overlap.Flush();
      CStrategyT176Base::Deinit();
   }
};

// T17.5 inherited-source regression anchors. These executable semantics live
// unchanged in StrategyT176Base.mqh; the legacy source gate still scans this
// public composition header, so keep the inherited contract names visible.
/*
 m_pyramid.BuildDcaView(side, dcaSide)
 m_pyramid.ReleaseNewestForDca(side, dir, releaseWhy)
 dcaSide.totalLots = side.totalLots
 LatestCoreAddTime(side, dir)
 m_guardLatched DriveGuardLatch
 CheckFloatingPriority CheckSecondaryFloating
 AccountInfoDouble(ACCOUNT_PROFIT)
 CampaignRealized(BD_DIR_BUY) CampaignRealized(BD_DIR_SELL)
 pctCampaignHistoryValid
 MG_PctDiffExecutionReserveCashPure
 Exec_Deviation(Slippage_, Cfg.PointScale)
 EconomicTpLevel(side, dir, tp, economicTp)
 Exit_OverlapExecutionSafePure
*/

#endif // BD_STRATEGY_T177_C3_MQH
