//+------------------------------------------------------------------+
//| CorePyramidT177Anchor.mqh — T17.7 C2 selectable Core anchor     |
//| DYNAMIC = byte-semantic T17.6 Drive path. FIRST_CORE = fixed     |
//| exact-Magic campaign seed price + cumulative serial ladder.      |
//+------------------------------------------------------------------+
#ifndef BD_CORE_PYRAMID_T177_ANCHOR_MQH
#define BD_CORE_PYRAMID_T177_ANCHOR_MQH

#include "PyramidAnchorT177.mqh"
#include <BlackDragon/EntryFilters.mqh> // canonical BD_DIR_BUY/SELL definitions
#include <BlackDragon/BasketManager.mqh>
#include <BlackDragon/ExecutionLayer.mqh>
#include <BlackDragon/Recovery/RecoveryEngine.mqh>
#include <BlackDragon/Recovery/RecoveryMath.mqh>

// Reuse the verified T17.6 engine as a protected base. Dependencies are
// pre-included above so the visibility macro affects CorePyramid itself only.
#define private protected
#define CCorePyramidEngine CCorePyramidEngineT176Base
#include "CorePyramid.mqh"
#undef CCorePyramidEngine
#undef private

class CCorePyramidEngine : public CCorePyramidEngineT176Base
{
private:
   double m_firstCorePrice[2];
   ulong  m_firstCoreDeal[2];

   bool RefreshFirstCoreIdentity(const BasketSide &side,
                                 const int dir)
   {
      if(dir < BD_DIR_BUY || dir > BD_DIR_SELL) return false;
      if(CorePyramidAnchorMode_ != pyramid_anchor_FIRST_CORE_CUMULATIVE)
      {
         m_firstCorePrice[dir] = 0.0;
         m_firstCoreDeal[dir] = 0;
         return true;
      }
      if(CorePyramidMode_ == pyramid_TAT || side.count <= 0)
      {
         m_firstCorePrice[dir] = 0.0;
         m_firstCoreDeal[dir] = 0;
         return true;
      }

      ulong deal = m_campaignStartDeal[dir];
      if(deal == 0) return false;
      if(m_firstCoreDeal[dir] == deal && m_firstCorePrice[dir] > 0.0)
         return true;
      if(!HistoryDealSelect(deal)) return false;

      long expectedType = dir == BD_DIR_BUY ? DEAL_TYPE_BUY : DEAL_TYPE_SELL;
      if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol ||
         HistoryDealGetInteger(deal, DEAL_MAGIC) != (long)Magic ||
         HistoryDealGetInteger(deal, DEAL_ENTRY) != DEAL_ENTRY_IN ||
         HistoryDealGetInteger(deal, DEAL_TYPE) != expectedType ||
         Pyramid_IsComment(HistoryDealGetString(deal, DEAL_COMMENT)))
         return false;

      double price = HistoryDealGetDouble(deal, DEAL_PRICE);
      if(price <= 0.0) return false;
      m_firstCoreDeal[dir] = deal;
      m_firstCorePrice[dir] = price;
      return true;
   }

   bool TryAddFirstCore(const EAContext &ctx, const BasketSide &side, const int dir,
                        const int maxOrders, const datetime lastBar,
                        const SPyramidBook &book,
                        const SPyramidCampaignStats &stats,
                        CRecoveryEngine *recovery, string &why)
   {
      if(CorePyramidMode_ == pyramid_TAT || PyramidMaxAdds_ <= 0 || !stats.ready) return false;
      if(side.count <= 0 || book.nonPyramidCount < 1) return false;

      if(!Pyramid_ConcurrentAddAllowedPure(book.pyramidCount, PyramidMaxAdds_))
      { why = "BLOCK_MAX_CONCURRENT"; return false; }
      if(CorePyramidMode_ == pyramid_CHU_KY_SACH && stats.exitDeals > 0)
      { why = "BLOCK_CLEAN_CYCLE_EXITED"; return false; }
      if(side.count >= maxOrders) { why = "BLOCK_MAX_ORDERS"; return false; }
      if(PyramidReserveDcaSlots_ > 0 && side.count + 1 + PyramidReserveDcaSlots_ > maxOrders)
      { why = "BLOCK_DCA_RESERVE"; return false; }
      if(!RecoveryAllowsAdd(recovery, dir)) { why = "BLOCK_RECOVERY"; return false; }
      if(m_exec.BusyOpen(dir) || m_exec.HasAnyPendingClose() ||
         m_exec.HasPendingForCycle(CycleKey(dir)))
      { why = "BLOCK_PENDING"; return false; }
      if(!TrendAllows(ctx, dir)) { why = "BLOCK_TREND"; return false; }

      datetime lastMutation = LatestPyramidMutationTimeInternal(side, dir);
      if(lastBar == ctx.barTime ||
         !Pyramid_T173AddAfterMutationAllowsPure(lastMutation, ctx.now,
                                                  ctx.barTime, MinuteStop))
      { why = "BLOCK_TIMING_MUTATION"; return false; }

      double pip = PipSize(ctx);
      if(pip <= 0.0) return false;
      if(PyramidMinLockedProfitPips_ > 0.0)
      {
         double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
         double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
         if(!Pyramid_EconomicMinLockedAllowsPure(side.totalProfit,
                                                  stats.realizedCash,
                                                  PyramidMinLockedProfitPips_,
                                                  side.totalLots,
                                                  tickValue,
                                                  tickSize,
                                                  pip))
         { why = "BLOCK_MIN_PROFIT_ECONOMIC"; return false; }
      }
      if(PyramidMinRoomToTPPips_ > 0.0)
      {
         double room = Pyramid_RoomToTpPipsPure(dir, side.tpLevel,
                                                ctx.bid, ctx.ask, pip);
         if(room < PyramidMinRoomToTPPips_ - 1e-9)
         { why = "BLOCK_TP_ROOM"; return false; }
      }

      int level = Pyramid_NextSerialLevelPure(stats.highestLevel);
      double anchor = m_firstCorePrice[dir];
      if(anchor <= 0.0)
      { why = "BLOCK_FIRST_CORE_IDENTITY"; return false; }
      double gapPips = Pyramid_T177CumulativeDistancePure(m_distance, level);
      if(gapPips <= 0.0)
      { why = "BLOCK_FIRST_CORE_DISTANCE"; return false; }
      if(!Pyramid_T177FirstCoreGapHitPure(dir, anchor, ctx.bid, ctx.ask,
                                          gapPips * pip))
      { why = "BLOCK_GAP"; return false; }

      double candidate = ConfiguredLot(side, level);
      if(candidate <= 0.0) return false;

      if(PyramidLotMode_ == pyramid_LOT_CHUOI)
      {
         if(candidate > Cfg.MaxLot) candidate = Cfg.MaxLot;
         candidate = Grid_NormalizeVolume(candidate);
         if(candidate <= 0.0) return false;
         if(PyramidMaxTotalLots_ > 0.0 &&
            side.totalLots + candidate > PyramidMaxTotalLots_ + 1e-9)
         { why = "BLOCK_FIXED_LOT_TOTAL_CAP"; return false; }

         double riskPerLot = RiskCashPerLot(ctx);
         double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
         double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
         if(riskPerLot <= 0.0 || tickSize <= 0.0 || tickValue <= 0.0)
         { why = "BLOCK_FIXED_LOT_RISK_METADATA"; return false; }
         double minLockedCash = Pyramid_PipsCashPure(PyramidMinLockedProfitPips_,
                                                      side.totalLots,
                                                      tickValue,
                                                      tickSize,
                                                      pip);
         double openRiskCash = book.pyramidLots * riskPerLot;
         double candidateRiskCash = candidate * riskPerLot;
         double fundingCash = side.totalProfit - book.pyramidProfit + stats.realizedCash;
         double requiredCash = minLockedCash + openRiskCash + candidateRiskCash;
         if(!Pyramid_FixedLotPeelReserveAllowsPure(side.totalProfit,
                                                    book.pyramidProfit,
                                                    stats.realizedCash,
                                                    minLockedCash,
                                                    openRiskCash,
                                                    candidateRiskCash))
         {
            why = "BLOCK_FIXED_LOT_PEEL_RESERVE funding=" +
                  DoubleToString(fundingCash, 2) + " required=" +
                  DoubleToString(requiredCash, 2) + " livePyramidFloating=" +
                  DoubleToString(book.pyramidProfit, 2);
            return false;
         }
      }
      else
      {
         if(!Pyramid_RiskModeReadyPure(PyramidLotMode_, PyramidRiskBudgetPercent_))
         { why = "BLOCK_RISK_MODE_ZERO_BUDGET"; return false; }
         if(Pyramid_RiskBudgetAppliesPure(PyramidLotMode_, PyramidRiskBudgetPercent_))
         {
            double riskPerLot = RiskCashPerLot(ctx);
            if(riskPerLot <= 0.0) return false;
            double openRiskCash = book.pyramidLots * riskPerLot;
            double availableRiskCash = Pyramid_AvailableRiskCashPure(side.totalProfit,
                                                                     stats.realizedCash,
                                                                     openRiskCash,
                                                                     PyramidRiskBudgetPercent_);
            double riskCap = availableRiskCash / riskPerLot;
            if(riskCap <= 0.0) { why = "BLOCK_RISK_BUDGET"; return false; }
            if(candidate > riskCap) candidate = riskCap;
         }

         if(PyramidMaxTotalLots_ > 0.0)
         {
            double available = PyramidMaxTotalLots_ - side.totalLots;
            if(available <= 0.0) { why = "BLOCK_TOTAL_LOTS"; return false; }
            if(candidate > available) candidate = available;
         }
         if(candidate > Cfg.MaxLot) candidate = Cfg.MaxLot;
         candidate = Pyramid_NormalizeFloor(candidate);
         if(candidate <= 0.0) { why = "BLOCK_VOLUME_GRID"; return false; }
      }

      string comment = Pyramid_BuildComment(dir, level);
      if(!m_exec.OpenMarketOwned(dir, candidate, (long)Magic,
                                 CycleKey(dir),
                                 EXEC_CMD_CORE_PYRAMID_OPEN,
                                 EXEC_RECONCILE_FAIL_CLOSED,
                                 comment))
      {
         why = "Không gửi được lệnh nhồi dương Core serial=" + (string)level;
         return false;
      }

      double targetPrice = Pyramid_T177FirstCoreTriggerPricePure(dir, anchor,
                                                                 gapPips * pip);
      double triggerPrice = dir == BD_DIR_BUY ? ctx.ask : ctx.bid;
      why = "T17.7 Pyramid Core mở serial=" + (string)level +
            " concurrent=" + (string)(book.pyramidCount + 1) +
            "/" + (string)PyramidMaxAdds_ +
            " lot=" + DoubleToString(candidate, 2) +
            " anchor=" + DoubleToString(anchor, ctx.digits) +
            " anchorKind=first-core-cumulative" +
            " target=" + DoubleToString(targetPrice, ctx.digits) +
            " trigger=" + DoubleToString(triggerPrice, ctx.digits) +
            " cumulativeGapPips=" + DoubleToString(gapPips, 2) +
            " economic=" + DoubleToString(Pyramid_CampaignEconomicProfitPure(side.totalProfit,
                                                                               stats.realizedCash), 2) +
            " reserveFunding=" + DoubleToString(side.totalProfit - book.pyramidProfit +
                                                  stats.realizedCash, 2);
      return true;
   }

public:
   CCorePyramidEngine(void) : CCorePyramidEngineT176Base()
   {
      for(int d = 0; d < 2; d++)
      {
         m_firstCorePrice[d] = 0.0;
         m_firstCoreDeal[d] = 0;
      }
   }

   bool Init(CExecutionLayer *exec, string &why)
   {
      why = "";
      if(!Pyramid_T177AnchorModeValid(CorePyramidAnchorMode_))
      {
         why = "Chế độ mốc Pyramid Core không hợp lệ";
         return false;
      }
      return CCorePyramidEngineT176Base::Init(exec, why);
   }

   bool RefreshCampaignStats(const BasketSide &side, const int dir, const datetime now)
   {
      bool ok = CCorePyramidEngineT176Base::RefreshCampaignStats(side, dir, now);
      if(dir < BD_DIR_BUY || dir > BD_DIR_SELL) return false;
      if(!ok)
      {
         if(CorePyramidAnchorMode_ == pyramid_anchor_FIRST_CORE_CUMULATIVE)
         {
            m_firstCorePrice[dir] = 0.0;
            m_firstCoreDeal[dir] = 0;
         }
         return false;
      }
      if(!RefreshFirstCoreIdentity(side, dir))
      {
         m_firstCorePrice[dir] = 0.0;
         m_firstCoreDeal[dir] = 0;
         return false;
      }
      return true;
   }

   double CampaignFirstCorePrice(const int dir) const
   {
      if(dir < BD_DIR_BUY || dir > BD_DIR_SELL) return 0.0;
      return m_firstCorePrice[dir];
   }

   bool Drive(const EAContext &ctx, const BasketSide &side, const int dir,
              const int maxOrders, CRecoveryEngine *recovery,
              const bool allowAdd, const datetime lastBar, string &why)
   {
      // Exact backward path: DYNAMIC delegates to the verified T17.6 engine.
      if(CorePyramidAnchorMode_ == pyramid_anchor_DYNAMIC)
         return CCorePyramidEngineT176Base::Drive(ctx, side, dir, maxOrders,
                                                  recovery, allowAdd, lastBar, why);

      why = "";
      if(CorePyramidMode_ == pyramid_TAT || side.count <= 0 || m_exec == NULL)
         return false;

      SPyramidBook book;
      Pyramid_ReadBook(side, book);

      bool recoveryOwns = false;
      if(RecoveryMode_ == recovery_ACTIVE && recovery != NULL && recovery.ActiveReady())
      {
         SRecoveryCycle c;
         recovery.GetCycle(dir == BD_DIR_BUY ? recovery_CORE_BUY : recovery_CORE_SELL, c);
         recoveryOwns = c.state != recovery_CORE_ONLY;
      }
      if(!recoveryOwns && TryPeel(ctx, dir, book, why)) return true;
      if(recoveryOwns || !allowAdd || !CampaignHistoryReady(dir)) return false;
      return TryAddFirstCore(ctx, side, dir, maxOrders, lastBar, book,
                             m_stats[dir], recovery, why);
   }
};

#endif // BD_CORE_PYRAMID_T177_ANCHOR_MQH
