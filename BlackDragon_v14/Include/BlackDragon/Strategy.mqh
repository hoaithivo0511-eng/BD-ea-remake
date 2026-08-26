//+------------------------------------------------------------------+
//| Strategy.mqh — T17.12 recovery-aware exit wrapper               |
//| T17.7 durable Overlap + T17.9 REAL-TP + T17.11 admission stay   |
//| intact; T17.12 adds economic admission before Recovery exits.    |
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
#include "Recovery/RecoveryT1712EconomicPolicy.mqh"

class CStrategy : public CStrategyT176Base
{
private:
   COverlapT177Coordinator m_overlap;

   bool RecoveryOwnsExitSideT1712(const int dir) const
   {
      if(RecoveryMode_ != recovery_ACTIVE || m_recovery == NULL) return false;
      eRecoveryCoreDirection rdir = RecoveryDir(dir);
      SRecoveryCycle cycle;
      m_recovery.GetCycle(rdir, cycle);
      bool liveExposure = m_recovery.T16HasExposure(rdir);
      return liveExposure ||
             (cycle.state != recovery_CORE_ONLY && cycle.state != recovery_COMPLETED);
   }

   double NominalTpTargetCashT1712(const BasketSide &side) const
   {
      double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      return Recovery_T1712NominalTargetCashPure(side.tpLevel, side.breakeven,
                                                  side.totalLots,
                                                  tickSize, tickValue);
   }

   bool BuildRecoveryExitSnapshotT1712(const EAContext &ctx,
                                       const BasketSide &side,
                                       const int dir,
                                       const double requiredTargetCash,
                                       SRecoveryT1712ExitEconomicSnapshot &s,
                                       string &why) const
   {
      why = "";
      Recovery_T1712SnapshotReset(s);
      s.recoveryOwns = RecoveryOwnsExitSideT1712(dir);
      s.coreFloating = side.totalProfit;
      s.coreLots = side.totalLots;
      s.requiredTargetCash = requiredTargetCash;
      s.currentExitPrice = dir == BD_DIR_BUY ? ctx.bid : ctx.ask;

      // Exact Core-only parity: no new economic condition participates.
      if(!s.recoveryOwns)
      {
         s.reserveCash = 0.0;
         s.valid = true;
         return true;
      }

      if(m_recovery == NULL || !m_recovery.ActiveReady())
      { why = "Recovery runtime chưa ready để chứng minh whole-cycle economics"; return false; }
      if(side.count <= 0 || side.totalLots <= 0.0 || s.currentExitPrice <= 0.0)
      { why = "Core side thiếu live exposure/price cho economic snapshot"; return false; }

      double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      if(tickSize <= 0.0 || tickValue <= 0.0 ||
         !Recovery_T1712FinitePure(requiredTargetCash))
      { why = "tick economics/target cash không khả dụng"; return false; }

      if(CorePyramidMode_ != pyramid_TAT && m_pyramid != NULL)
      {
         if(!m_pyramid.CampaignHistoryReady(dir))
         { why = "Pyramid campaign history chưa ready"; return false; }
         s.pyramidRealized = m_pyramid.CampaignRealized(dir);
      }

      // Reuse the existing durable T5/T16 ledger. Never substitute the
      // T16.5 day-realized cache for cycle economics.
      SRecoveryT5CycleRuntime rt;
      m_recovery.GetT5Runtime(RecoveryDir(dir), rt);
      s.recoveryCycleRealized = rt.ledger.hedgeNetCash - rt.ledger.coreLossSpent;

      long wantedHedgeType = dir == BD_DIR_BUY ? POSITION_TYPE_SELL
                                                : POSITION_TYPE_BUY;
      int recoveryRequests = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol ||
            PositionGetInteger(POSITION_MAGIC) != (long)RecoveryMagic_ ||
            PositionGetInteger(POSITION_TYPE) != wantedHedgeType)
            continue;
         double lots = PositionGetDouble(POSITION_VOLUME);
         if(lots <= 0.0)
         { why = "Recovery position có volume không hợp lệ"; return false; }
         s.recoveryLots += lots;
         s.recoveryFloating += PositionGetDouble(POSITION_PROFIT) +
                               PositionGetDouble(POSITION_SWAP);
         recoveryRequests++;
      }

      s.closeRequests = side.count + recoveryRequests;
      double totalLots = s.coreLots + s.recoveryLots;
      s.reserveCash = Recovery_T1712LiquidationReserveCashPure(
         MathMax(ctx.ask - ctx.bid, 0.0), Cfg.SlippagePrice,
         totalLots, s.closeRequests, tickSize, tickValue);
      s.netCashSlopePerPrice = Recovery_T1712CashSlopePerPricePure(
         dir == BD_DIR_BUY, s.coreLots, s.recoveryLots, tickSize, tickValue);

      s.valid = s.closeRequests > 0 &&
                Recovery_T1712FinitePure(s.coreFloating) &&
                Recovery_T1712FinitePure(s.recoveryFloating) &&
                Recovery_T1712FinitePure(s.pyramidRealized) &&
                Recovery_T1712FinitePure(s.recoveryCycleRealized) &&
                Recovery_T1712FinitePure(s.requiredTargetCash) &&
                Recovery_T1712FinitePure(s.reserveCash) &&
                Recovery_T1712FinitePure(s.netCashSlopePerPrice);
      if(!s.valid) why = "whole-cycle snapshot chứa economics không hợp lệ";
      return s.valid;
   }

   bool RecoveryExitFundedT1712(const EAContext &ctx,
                                const BasketSide &side,
                                const int dir,
                                const eExitKind kind) const
   {
      if(!RecoveryOwnsExitSideT1712(dir)) return true;
      double requiredTargetCash = kind == EXIT_TP ? NominalTpTargetCashT1712(side) : 0.0;
      SRecoveryT1712ExitEconomicSnapshot s;
      string why = "";
      if(!BuildRecoveryExitSnapshotT1712(ctx, side, dir, requiredTargetCash, s, why))
      {
         Log_WarnEvery("Recovery", "t1712exitinvalid" + (string)dir + "_" + (string)(int)kind,
                       "T17.12 WAIT " + (dir == BD_DIR_BUY ? "BUY" : "SELL") +
                       " | chưa chứng minh được whole-cycle exit economics | " + why,
                       Recovery_T165WaitLogSecondsPure(RecoveryWaitLogSeconds_));
         return false;
      }
      if(Recovery_T1712SnapshotFundedPure(s)) return true;
      Log_WarnEvery("Recovery", "t1712exitwait" + (string)dir + "_" + (string)(int)kind,
                    "T17.12 WAIT " + (dir == BD_DIR_BUY ? "BUY" : "SELL") +
                    " | whole-cycle=" + DoubleToString(Recovery_T1712SnapshotCashPure(s),2) +
                    " < target+reserve=" +
                    DoubleToString(MathMax(s.requiredTargetCash,0.0)+MathMax(s.reserveCash,0.0),2),
                    Recovery_T165WaitLogSecondsPure(RecoveryWaitLogSeconds_));
      return false;
   }

   bool ProjectedRecoveryRealTpT1712(const EAContext &ctx,
                                     const BasketSide &side,
                                     const int dir,
                                     const double legacyTp,
                                     double &projectedTp) const
   {
      projectedTp = legacyTp;
      if(!RecoveryOwnsExitSideT1712(dir)) return true;
      double requiredTargetCash = NominalTpTargetCashT1712(side);
      SRecoveryT1712ExitEconomicSnapshot s;
      string why = "";
      if(!BuildRecoveryExitSnapshotT1712(ctx, side, dir, requiredTargetCash, s, why))
      {
         Log_WarnEvery("Recovery", "t1712realtpinvalid" + (string)dir,
                       "T17.12 REAL TP WAIT " + (dir == BD_DIR_BUY ? "BUY" : "SELL")+
                       " | " + why,
                       Recovery_T165WaitLogSecondsPure(RecoveryWaitLogSeconds_));
         projectedTp = 0.0;
         return false;
      }

      double raw = 0.0;
      bool isBuy = dir == BD_DIR_BUY;
      if(!Recovery_T1712ProjectedTpPure(isBuy, s.currentExitPrice, legacyTp,
                                        s.coreFloating, s.recoveryFloating,
                                        s.pyramidRealized, s.requiredTargetCash,
                                        s.reserveCash, s.netCashSlopePerPrice,
                                        raw, s.recoveryCycleRealized))
      {
         Log_WarnEvery("Recovery", "t1712realtpslope" + (string)dir,
                       "T17.12 REAL TP WAIT " + (dir == BD_DIR_BUY ? "BUY" : "SELL")+
                       " | không có finite Core-favorable TP đủ whole-cycle economics",
                       Recovery_T165WaitLogSecondsPure(RecoveryWaitLogSeconds_));
         projectedTp = 0.0;
         return false;
      }

      double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tickSize <= 0.0)
      { projectedTp = 0.0; return false; }
      double tickUnits = raw / tickSize;
      double aligned = isBuy ? MathCeil(tickUnits - 1e-10) * tickSize
                             : MathFloor(tickUnits + 1e-10) * tickSize;
      projectedTp = NormalizeDouble(aligned, ctx.digits);
      if(projectedTp <= 0.0 ||
         (isBuy && projectedTp + 1e-12 < legacyTp) ||
         (!isBuy && projectedTp > legacyTp + 1e-12) ||
         !Recovery_T1712ProjectedPriceFundedPure(s, projectedTp))
      {
         projectedTp = 0.0;
         return false;
      }
      return true;
   }

   bool RecoveryRealTrailLevelSafeT1712(const EAContext &ctx,
                                         const BasketSide &side,
                                         const int dir,
                                         const double trailSl) const
   {
      if(trailSl <= 0.0 || !RecoveryOwnsExitSideT1712(dir)) return true;
      SRecoveryT1712ExitEconomicSnapshot s;
      string why = "";
      if(!BuildRecoveryExitSnapshotT1712(ctx, side, dir, 0.0, s, why) ||
         !Recovery_T1712ProjectedPriceFundedPure(s, trailSl))
      {
         Log_WarnEvery("Recovery", "t1712realtrail" + (string)dir,
                       "T17.12 REAL trailing WAIT " +
                       (dir == BD_DIR_BUY ? "BUY" : "SELL")+
                       " | broker trail level chưa đủ whole-cycle liquidation reserve"+
                       (why == "" ? "" : " | " + why),
                       Recovery_T165WaitLogSecondsPure(RecoveryWaitLogSeconds_));
         return false;
      }
      return true;
   }

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

      // T17.12: only Recovery-owned TP/Trail closes get the new economic gate.
      // Core-only and SL semantics remain byte-for-behavior equivalent.
      if((d.kind == EXIT_TP || d.kind == EXIT_TRAIL) &&
         !RecoveryExitFundedT1712(ctx, side, dir, d.kind))
         return false;

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

   void ApplyRealLevelsT1712(const EAContext &ctx,
                             const BasketSide &side,
                             const bool isBuy)
   {
      double sl, tp;
      if(!m_exitPolicy.RealLevels(ctx, side, isBuy, sl, tp)) return;
      int dir = isBuy ? BD_DIR_BUY : BD_DIR_SELL;

      if(TP_Mode == mode_Real && Cfg.TP != 0 && m_pyramid != NULL)
      {
         double economicTp = tp;
         if(m_pyramid.EconomicTpLevel(side, dir, tp, economicTp))
            tp = NormalizeDouble(economicTp, ctx.digits);
         else
            tp = 0.0;
      }

      // Compute the Recovery-aware broker target BEFORE preparing/updating the
      // T17.9 durable epoch. A flat/adverse net slope clears unsafe Core TP.
      if(TP_Mode == mode_Real && Cfg.TP != 0 && tp > 0.0 &&
         RecoveryMode_ == recovery_ACTIVE)
      {
         double projectedTp = tp;
         if(ProjectedRecoveryRealTpT1712(ctx, side, dir, tp, projectedTp))
            tp = projectedTp;
         else
            tp = 0.0;
      }

      if(TP_Mode == mode_Real && Cfg.TP != 0 && tp > 0.0 &&
         RecoveryMode_ == recovery_ACTIVE && m_recoveryExit != NULL &&
         !m_recoveryExit.PrepareRealTpEpoch(RecoveryDir(dir), tp, ctx.now))
         return;

      // Real trailing is also a broker-side Core-only trigger. If the trailing
      // candidate would violate whole-cycle economics, retain any independent
      // REAL SL risk limit but clear/defer only the trailing contribution.
      if(Trail_Mode == mode_Real && side.trailArmed && side.trailLevel > 0.0)
      {
         double baseRiskSl = (SL_Mode == mode_Real && Cfg.SL != 0) ?
                             NormalizeDouble(side.slLevel, ctx.digits) : 0.0;
         bool trailOwnsSl = isBuy ? (side.trailLevel > baseRiskSl) :
                                     (baseRiskSl == 0.0 || side.trailLevel < baseRiskSl);
         if(trailOwnsSl && !RecoveryRealTrailLevelSafeT1712(ctx, side, dir, sl))
            sl = baseRiskSl;
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
         ulong ticket=side.pos[i].ticket;
         long wantedType=isBuy ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
         if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
         ulong selectedTicket=(ulong)PositionGetInteger(POSITION_TICKET);
         bool symbolMatches=PositionGetString(POSITION_SYMBOL)==_Symbol;
         bool ownerMatches=Basket_OwnsMagic(PositionGetInteger(POSITION_MAGIC),
                                             (long)Magic,flag_Hand_Ord);
         bool typeMatches=PositionGetInteger(POSITION_TYPE)==wantedType;
         double liveVolume=PositionGetDouble(POSITION_VOLUME);
         if(!Recovery_T179ModifyCandidatePure(ticket,true,selectedTicket,
                                               symbolMatches,ownerMatches,
                                               typeMatches,liveVolume)) continue;
         double curSl = NormalizeDouble(PositionGetDouble(POSITION_SL), ctx.digits);
         double curTp = NormalizeDouble(PositionGetDouble(POSITION_TP), ctx.digits);
         if(curSl != sl || curTp != tp)
         {
            if(m_exec.HasPendingModify(ticket)) continue;
            if(m_exec.ModifySlTp(ticket, sl, tp)) modified = true;
            else if(PositionSelectByTicket(ticket))
               Log_Warn("Strategy", "sltp", "modify SL/TP failed live ticket " + (string)ticket);
         }
      }
      if(modified) m_basket.Invalidate();
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

      if(ApplyGuardPriority(ctx))
      {
         if(panelOpenBuy || panelOpenSell)
            Log_Warn("Strategy", "guardclose",
                     "panel open ignored because MoneyGuard close latch owns Strategy");
         return;
      }

      if(m_recoveryExit != NULL && RecoveryMode_ == recovery_ACTIVE)
      {
         m_recoveryExit.ObserveRealTpSettlement(recovery_CORE_BUY,
                                                 ctx.bid,ctx.ask,ctx.now);
         m_recoveryExit.ObserveRealTpSettlement(recovery_CORE_SELL,
                                                 ctx.bid,ctx.ask,ctx.now);
      }

      if(m_pyramid != NULL &&
         (m_pyramid.HasPending(BD_DIR_BUY) || m_pyramid.HasPending(BD_DIR_SELL)))
      {
         Log_WarnEvery("Pyramid", "strictpending",
                       "T17 strict Pyramid mutation đang chờ broker/reconcile; tạm khóa mutation Strategy cho tới khi xác định outcome",
                       Recovery_T165WaitLogSecondsPure(RecoveryWaitLogSeconds_));
         return;
      }

      if(DriveOverlapUrgent(ctx)) return;

      if(m_exec.HasAnyPendingClose())
      {
         if(panelOpenBuy || panelOpenSell)
            Log_Warn("Strategy", "pendingclose",
                     "panel open ignored while an async close is pending");
         return;
      }

      RefreshPyramidCampaigns(ctx);

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
         if(BlocksRealTpAdd(BD_DIR_BUY))
            Log_WarnEvery("Recovery", "t179panelbuy",
                          "CHỜ BUY | Broker TP cohort đang settle; khóa mở thêm cùng side",
                          Recovery_T165WaitLogSecondsPure(RecoveryWaitLogSeconds_));
         else if(m_overlap.BlocksSide(BD_DIR_BUY))
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
         if(BlocksRealTpAdd(BD_DIR_SELL))
            Log_WarnEvery("Recovery", "t179panelsell",
                          "CHỜ SELL | Broker TP cohort đang settle; khóa mở thêm cùng side",
                          Recovery_T165WaitLogSecondsPure(RecoveryWaitLogSeconds_));
         else if(m_overlap.BlocksSide(BD_DIR_SELL))
            Log_WarnEvery("Overlap", "panelsell",
                          "CHỜ SELL | Không mở thêm lệnh khi cặp Overlap đang xử lý",
                          Recovery_T165WaitLogSecondsPure(RecoveryWaitLogSeconds_));
         else if(m_exec.BusyOpen(BD_DIR_SELL))
            Log_Warn("Strategy", "panelbusy", "panel Open Sell ignored: async open in flight");
         else if(m_exec.OpenMarket(BD_DIR_SELL, Cfg.EditLot, m_basket.sell.count + 1))
         { m_basket.Invalidate(); panelMutation = true; }
      }
      if(panelMutation) return;

      if(m_pyramid != NULL)
      {
         string pyrWhy = "";
         datetime buyLastBar = m_basket.LastBuyBar();
         bool allowPyramidAddBuy = m_newSeriesFilters.Allow(ctx, BD_DIR_BUY);
         if(m_basket.buy.count > 0 && !m_overlap.BlocksSide(BD_DIR_BUY) &&
            !BlocksRealTpAdd(BD_DIR_BUY))
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
         if(m_basket.sell.count > 0 && !m_overlap.BlocksSide(BD_DIR_SELL) &&
            !BlocksRealTpAdd(BD_DIR_SELL))
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

      ApplyRealLevelsT1712(ctx, m_basket.buy,  true);
      ApplyRealLevelsT1712(ctx, m_basket.sell, false);
   }

   void Deinit()
   {
      m_overlap.Flush();
      CStrategyT176Base::Deinit();
   }
};

// T17.5 inherited-source regression anchors. These executable semantics live
// unchanged in StrategyT176Base.mqh; keep the inherited contract names visible.
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
