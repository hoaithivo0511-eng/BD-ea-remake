//+------------------------------------------------------------------+
//| CorePyramid.mqh — T17.4 campaign-safe serial re-arm + DCA       |
//| Campaign economics survive epochs; historical price extreme does|
//| not. Peel exit creates temporary hysteresis anchor only.         |
//+------------------------------------------------------------------+
#ifndef BD_CORE_PYRAMID_MQH
#define BD_CORE_PYRAMID_MQH

#include "PyramidConfig.mqh"
#include <BlackDragon/BasketManager.mqh>
#include <BlackDragon/ExecutionLayer.mqh>
#include <BlackDragon/Recovery/RecoveryEngine.mqh>
#include <BlackDragon/Recovery/RecoveryMath.mqh>

struct SPyramidBook
{
   int pyramidCount;
   int nonPyramidCount;
   int highestLevel;
   ulong newestPyramidTicket;
   double newestPyramidOpen;
   datetime newestPyramidTime;
   long newestPyramidTimeMsc;
   ulong newestNonPyramidTicket;
   datetime newestNonPyramidTime;
   long newestNonPyramidTimeMsc;
   double pyramidLots;
   double pyramidProfit;
   double nonPyramidLots;
   ulong seedTicket;
   datetime seedOpenTime;
};

struct SPyramidCampaignStats
{
   bool ready;
   int addCount;
   int exitDeals;
   int highestLevel;
   double lastSerialEntryPrice;
   datetime lastAddTime;
   long lastAddTimeMsc;
   ulong lastAddDeal;
   datetime lastExitTime;
   long lastExitTimeMsc;
   ulong lastExitDeal;
   double lastExitPrice;
   datetime lastMutationTime;
   long lastMutationTimeMsc;
   ulong lastMutationDeal;
   bool lastMutationWasExit;
   double realizedCash;
};

void Pyramid_BookReset(SPyramidBook &b)
{
   ZeroMemory(b);
   b.highestLevel = 0;
}

void Pyramid_CampaignReset(SPyramidCampaignStats &s)
{
   ZeroMemory(s);
   s.ready = false;
}

bool Pyramid_TicketRole(const ulong ticket, bool &isPyramid, int &level)
{
   isPyramid = false;
   level = -1;
   if(ticket == 0 || !PositionSelectByTicket(ticket)) return false;
   string c = PositionGetString(POSITION_COMMENT);
   isPyramid = Pyramid_IsComment(c);
   if(isPyramid) level = Pyramid_LevelFromComment(c);
   return true;
}

void Pyramid_ReadBook(const BasketSide &side, SPyramidBook &book)
{
   Pyramid_BookReset(book);
   for(int i = 0; i < side.count; i++)
   {
      bool isP = false;
      int level = -1;
      if(!Pyramid_TicketRole(side.pos[i].ticket, isP, level)) continue;
      long openMsc = PositionGetInteger(POSITION_TIME_MSC);
      if(openMsc <= 0) openMsc = (long)side.pos[i].openTime * 1000;
      if(isP)
      {
         book.pyramidCount++;
         book.pyramidLots += side.pos[i].lots;
         book.pyramidProfit += side.pos[i].profit;
         if(level > book.highestLevel) book.highestLevel = level;
         if(openMsc > book.newestPyramidTimeMsc ||
            (openMsc == book.newestPyramidTimeMsc &&
             side.pos[i].ticket > book.newestPyramidTicket))
         {
            book.newestPyramidTimeMsc = openMsc;
            book.newestPyramidTime = side.pos[i].openTime;
            book.newestPyramidTicket = side.pos[i].ticket;
            book.newestPyramidOpen = side.pos[i].openPrice;
         }
      }
      else
      {
         book.nonPyramidCount++;
         book.nonPyramidLots += side.pos[i].lots;
         if(book.seedTicket == 0)
         {
            book.seedTicket = side.pos[i].ticket;
            book.seedOpenTime = side.pos[i].openTime;
         }
         if(openMsc > book.newestNonPyramidTimeMsc ||
            (openMsc == book.newestNonPyramidTimeMsc &&
             side.pos[i].ticket > book.newestNonPyramidTicket))
         {
            book.newestNonPyramidTimeMsc = openMsc;
            book.newestNonPyramidTime = side.pos[i].openTime;
            book.newestNonPyramidTicket = side.pos[i].ticket;
         }
      }
   }
}

void Pyramid_BuildDcaView(const BasketSide &source, BasketSide &out)
{
   ZeroMemory(out);
   ArrayResize(out.pos, 0);
   for(int i = 0; i < source.count; i++)
   {
      bool isP = false;
      int level = -1;
      if(!Pyramid_TicketRole(source.pos[i].ticket, isP, level) || isP) continue;
      int n = out.count;
      ArrayResize(out.pos, n + 1);
      out.pos[n] = source.pos[i];
      out.count++;
      out.totalLots += source.pos[i].lots;
      out.totalProfit += source.pos[i].profit;
   }
   out.breakeven = source.breakeven;
   out.tpLevel = source.tpLevel;
   out.slLevel = source.slLevel;
   out.trailLevel = source.trailLevel;
   out.trailArmed = source.trailArmed;
   out.extremePrice = source.extremePrice;
   out.swapSum = source.swapSum;
}

bool Pyramid_HasLegs(const BasketSide &side)
{
   SPyramidBook b;
   Pyramid_ReadBook(side, b);
   return b.pyramidCount > 0;
}

double Pyramid_NormalizeFloor(double lot)
{
   double vMin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vMax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(lot <= 0.0 || vMin <= 0.0 || vMax <= 0.0 || step <= 0.0) return 0.0;
   if(lot > vMax) lot = vMax;
   long units = (long)MathFloor(lot / step + 1e-9);
   double out = units * step;
   if(out + step * 1e-7 < vMin) return 0.0;
   return NormalizeDouble(out, 8);
}

bool Pyramid_UlongContains(const ulong &values[], const ulong value)
{
   for(int i = 0; i < ArraySize(values); i++)
      if(values[i] == value) return true;
   return false;
}

bool Pyramid_LaterDeal(const long tmsc, const ulong deal,
                       const long currentMsc, const ulong currentDeal)
{
   return tmsc > currentMsc || (tmsc == currentMsc && deal > currentDeal);
}

void Pyramid_RecordMutation(SPyramidCampaignStats &stats,
                            const long tmsc,
                            const datetime time,
                            const ulong deal,
                            const bool isExit)
{
   if(!Pyramid_LaterDeal(tmsc, deal, stats.lastMutationTimeMsc,
                         stats.lastMutationDeal)) return;
   stats.lastMutationTimeMsc = tmsc;
   stats.lastMutationTime = time;
   stats.lastMutationDeal = deal;
   stats.lastMutationWasExit = isExit;
}

// Campaign source of truth: serial identity + realized cash + latest mutation
// survive restart. T17.4 never uses lastSerialEntryPrice as permanent anchor.
bool Pyramid_ReadCampaignHistory(const int dir,
                                 const datetime seedOpenTime,
                                 const datetime now,
                                 SPyramidCampaignStats &stats)
{
   Pyramid_CampaignReset(stats);
   if(dir < BD_DIR_BUY || dir > BD_DIR_SELL || seedOpenTime <= 0 || now <= 0)
      return false;
   if(!HistorySelect(seedOpenTime, now + 1)) return false;

   ulong positionIds[];
   ArrayResize(positionIds, 0);
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0) continue;
      if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol ||
         HistoryDealGetInteger(deal, DEAL_MAGIC) != (long)Magic)
         continue;
      long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_IN && entry != DEAL_ENTRY_INOUT) continue;
      string c = HistoryDealGetString(deal, DEAL_COMMENT);
      if(!Pyramid_IsComment(c) || Pyramid_CommentFieldInt(c, "D=") != dir) continue;
      int level = Pyramid_LevelFromComment(c);
      if(level <= 0) return false;
      ulong positionId = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
      if(positionId == 0) return false;
      if(!Pyramid_UlongContains(positionIds, positionId))
      {
         int n = ArraySize(positionIds);
         ArrayResize(positionIds, n + 1);
         positionIds[n] = positionId;
         stats.addCount++;
      }
      datetime dealTime = (datetime)HistoryDealGetInteger(deal, DEAL_TIME);
      long dealMsc = HistoryDealGetInteger(deal, DEAL_TIME_MSC);
      if(dealMsc <= 0) dealMsc = (long)dealTime * 1000;
      if(Pyramid_LaterDeal(dealMsc, deal, stats.lastAddTimeMsc, stats.lastAddDeal))
      {
         stats.lastAddTimeMsc = dealMsc;
         stats.lastAddTime = dealTime;
         stats.lastAddDeal = deal;
      }
      Pyramid_RecordMutation(stats, dealMsc, dealTime, deal, false);
      if(level >= stats.highestLevel)
      {
         stats.highestLevel = level;
         stats.lastSerialEntryPrice = HistoryDealGetDouble(deal, DEAL_PRICE);
      }
   }

   for(int i = 0; i < total; i++)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0) continue;
      ulong positionId = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
      if(positionId == 0 || !Pyramid_UlongContains(positionIds, positionId)) continue;
      stats.realizedCash += HistoryDealGetDouble(deal, DEAL_PROFIT)
                          + HistoryDealGetDouble(deal, DEAL_SWAP)
                          + HistoryDealGetDouble(deal, DEAL_COMMISSION)
                          + HistoryDealGetDouble(deal, DEAL_FEE);
      long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
      if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY || entry == DEAL_ENTRY_INOUT)
      {
         stats.exitDeals++;
         datetime dealTime = (datetime)HistoryDealGetInteger(deal, DEAL_TIME);
         long dealMsc = HistoryDealGetInteger(deal, DEAL_TIME_MSC);
         if(dealMsc <= 0) dealMsc = (long)dealTime * 1000;
         if(Pyramid_LaterDeal(dealMsc, deal, stats.lastExitTimeMsc, stats.lastExitDeal))
         {
            stats.lastExitTimeMsc = dealMsc;
            stats.lastExitTime = dealTime;
            stats.lastExitDeal = deal;
            stats.lastExitPrice = HistoryDealGetDouble(deal, DEAL_PRICE);
         }
         Pyramid_RecordMutation(stats, dealMsc, dealTime, deal, true);
      }
   }

   stats.ready = true;
   return true;
}

class CCorePyramidEngine
{
private:
   CExecutionLayer *m_exec;
   double m_distance[];
   double m_lots[];
   double m_mult[];
   SPyramidCampaignStats m_stats[2];
   datetime m_statsAt[2];
   ulong m_statsSeed[2];
   int m_statsSideCount[2];
   double m_statsSideLots[2];
   ulong m_statsNewestPyramid[2];

   int CycleKey(const int dir) const { return 100 + dir; }

   double PipSize(const EAContext &ctx) const
   {
      return Recovery_PipSizePure(Sym_IsGold(), ctx.point, ctx.digits);
   }

   bool RecoveryAllowsAdd(CRecoveryEngine *recovery, const int dir) const
   {
      if(RecoveryMode_ != recovery_ACTIVE) return true;
      if(recovery == NULL || !recovery.ActiveReady()) return false;
      SRecoveryCycle c;
      recovery.GetCycle(dir == BD_DIR_BUY ? recovery_CORE_BUY : recovery_CORE_SELL, c);
      return c.state == recovery_CORE_ONLY;
   }

   double ConfiguredLot(const BasketSide &side, const int level) const
   {
      if(side.count <= 0 || level <= 0) return 0.0;
      if(PyramidLotMode_ == pyramid_LOT_CHUOI)
         return Pyramid_SeqValue(m_lots, level - 1);
      if(PyramidLotMode_ == pyramid_LOT_HE_SO)
         return Grid_ChainLot(side.pos[0].lots, level, m_mult, Cfg.MaxLot);
      return Cfg.MaxLot;
   }

   double RiskCashPerLot(const EAContext &ctx) const
   {
      double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double pip = PipSize(ctx);
      if(tickSize <= 0.0 || tickValue <= 0.0 || pip <= 0.0 || PyramidPeelGapPips_ <= 0.0)
         return 0.0;
      return PyramidPeelGapPips_ * pip / tickSize * tickValue;
   }

   bool TrendAllows(const EAContext &ctx, const int dir) const
   {
      if(!PyramidRequireTrend_) return true;
      return dir == BD_DIR_BUY ? !ctx.signalSell : !ctx.signalBuy;
   }

   datetime LatestLiveOpenTime(const BasketSide &side) const
   {
      datetime t = 0;
      for(int i = 0; i < side.count; i++)
         if(side.pos[i].openTime > t) t = side.pos[i].openTime;
      return t;
   }

   datetime LatestCoreAddTimeInternal(const BasketSide &side, const int dir) const
   {
      datetime t = LatestLiveOpenTime(side);
      if(dir >= BD_DIR_BUY && dir <= BD_DIR_SELL && m_stats[dir].ready &&
         m_stats[dir].lastAddTime > t)
         t = m_stats[dir].lastAddTime;
      return t;
   }

   datetime LatestPyramidMutationTimeInternal(const BasketSide &side, const int dir) const
   {
      datetime t = LatestLiveOpenTime(side);
      if(dir >= BD_DIR_BUY && dir <= BD_DIR_SELL && m_stats[dir].ready &&
         m_stats[dir].lastMutationTime > t)
         t = m_stats[dir].lastMutationTime;
      return t;
   }

   bool CloseNewestPyramid(const SPyramidBook &book, const int dir,
                           const string reason, string &why)
   {
      if(book.pyramidCount <= 0 || book.newestPyramidTicket == 0) return false;
      if(m_exec.HasAnyPendingClose() || m_exec.BusyOpen(dir) ||
         m_exec.HasPendingForCycle(CycleKey(dir))) return false;
      if(!PositionSelectByTicket(book.newestPyramidTicket)) return false;
      double volume = PositionGetDouble(POSITION_VOLUME);
      if(volume <= 0.0) return false;
      if(!m_exec.ClosePositionVolumeOwned(book.newestPyramidTicket, volume,
                                          (long)Magic, CycleKey(dir),
                                          EXEC_CMD_CORE_PYRAMID_CLOSE,
                                          EXEC_RECONCILE_FAIL_CLOSED))
      {
         why = reason + " không gửi được close Pyramid #" + (string)book.newestPyramidTicket;
         return false;
      }
      why = reason + " ticket=" + (string)book.newestPyramidTicket;
      return true;
   }

   bool TryPeel(const EAContext &ctx, const int dir,
                const SPyramidBook &book, string &why)
   {
      if(book.pyramidCount <= 0 || book.newestPyramidTicket == 0) return false;
      double pip = PipSize(ctx);
      if(pip <= 0.0) return false;
      if(!Pyramid_PeelHitPure(dir, book.newestPyramidOpen, ctx.bid, ctx.ask,
                              PyramidPeelGapPips_ * pip)) return false;
      return CloseNewestPyramid(book, dir, "T17.4 LIFO Peel", why);
   }

   bool TryAdd(const EAContext &ctx, const BasketSide &side, const int dir,
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
      double anchor = Pyramid_T173RearmAnchorPure(book.newestPyramidOpen,
                                                   side.breakeven,
                                                   book.newestNonPyramidTimeMsc,
                                                   stats.lastAddTimeMsc,
                                                   stats.lastExitTimeMsc,
                                                   stats.lastExitPrice);
      if(anchor <= 0.0) return false;
      double gapPips = Pyramid_SeqValue(m_distance, level - 1);
      if(!Pyramid_FavorableGapHitPure(dir, anchor, ctx.bid, ctx.ask, gapPips * pip))
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
      string anchorKind = book.newestNonPyramidTimeMsc > stats.lastAddTimeMsc ? "dca-BE" :
                          stats.lastExitTimeMsc > stats.lastAddTimeMsc ? "post-exit" :
                          book.pyramidCount > 0 ? "live-Pyramid" : "basket-BE";
      double triggerPrice = dir == BD_DIR_BUY ? ctx.ask : ctx.bid;
      why = "T17.4 Pyramid Core mở serial=" + (string)level +
            " concurrent=" + (string)(book.pyramidCount + 1) +
            "/" + (string)PyramidMaxAdds_ +
            " lot=" + DoubleToString(candidate, 2) +
            " anchor=" + DoubleToString(anchor, ctx.digits) +
            " anchorKind=" + anchorKind +
            " trigger=" + DoubleToString(triggerPrice, ctx.digits) +
            " gapPips=" + DoubleToString(gapPips, 2) +
            " economic=" + DoubleToString(Pyramid_CampaignEconomicProfitPure(side.totalProfit,
                                                                               stats.realizedCash), 2) +
            " reserveFunding=" + DoubleToString(side.totalProfit - book.pyramidProfit +
                                                  stats.realizedCash, 2);
      return true;
   }

public:
   CCorePyramidEngine(void)
   {
      m_exec = NULL;
      for(int d = 0; d < 2; d++)
      {
         Pyramid_CampaignReset(m_stats[d]);
         m_statsAt[d] = 0;
         m_statsSeed[d] = 0;
         m_statsSideCount[d] = -1;
         m_statsSideLots[d] = -1.0;
         m_statsNewestPyramid[d] = 0;
      }
   }

   bool Init(CExecutionLayer *exec, string &why)
   {
      why = "";
      m_exec = exec;
      if(m_exec == NULL) { why = "ExecutionLayer cho Pyramid không khả dụng"; return false; }
      if(!Pyramid_ValidateConfig(why)) return false;
      ArrayResize(m_distance, 0);
      ArrayResize(m_lots, 0);
      ArrayResize(m_mult, 0);
      if(CorePyramidMode_ == pyramid_TAT) return true;
      if(!Pyramid_ParsePositiveSequence(PyramidDistanceSequence_, m_distance))
      { why = "Không parse được chuỗi khoảng cách Pyramid"; return false; }
      if(PyramidLotMode_ == pyramid_LOT_CHUOI &&
         !Pyramid_ParsePositiveSequence(PyramidLotSequence_, m_lots))
      { why = "Không parse được chuỗi Lot Pyramid"; return false; }
      if(PyramidLotMode_ == pyramid_LOT_HE_SO &&
         !Pyramid_ParsePositiveSequence(PyramidMultiplierSequence_, m_mult))
      { why = "Không parse được chuỗi hệ số Pyramid"; return false; }
      return true;
   }

   bool HasLegs(const BasketSide &side) const
   {
      return Pyramid_HasLegs(side);
   }

   bool HasPending(const int dir) const
   {
      if(m_exec == NULL || dir < BD_DIR_BUY || dir > BD_DIR_SELL) return false;
      return m_exec.HasPendingForCycle(CycleKey(dir));
   }

   void BuildDcaView(const BasketSide &source, BasketSide &out) const
   {
      Pyramid_BuildDcaView(source, out);
   }

   datetime LatestCoreAddTime(const BasketSide &side, const int dir) const
   {
      return LatestCoreAddTimeInternal(side, dir);
   }

   // DCA priority path used only after every normal DCA gate has already hit
   // and broker slot capacity is full because Pyramid occupies the side.
   bool ReleaseNewestForDca(const BasketSide &side, const int dir, string &why)
   {
      why = "";
      if(m_exec == NULL || dir < BD_DIR_BUY || dir > BD_DIR_SELL) return false;
      SPyramidBook book;
      Pyramid_ReadBook(side, book);
      return CloseNewestPyramid(book, dir, "T17.4 DCA_PRIORITY_RELEASE", why);
   }

   bool RefreshCampaignStats(const BasketSide &side, const int dir, const datetime now)
   {
      if(dir < BD_DIR_BUY || dir > BD_DIR_SELL) return false;
      SPyramidBook book;
      Pyramid_ReadBook(side, book);

      if(CorePyramidMode_ == pyramid_TAT || side.count <= 0)
      {
         Pyramid_CampaignReset(m_stats[dir]);
         m_stats[dir].ready = true;
         m_statsAt[dir] = now;
         m_statsSeed[dir] = 0;
         m_statsSideCount[dir] = side.count;
         m_statsSideLots[dir] = side.totalLots;
         m_statsNewestPyramid[dir] = book.newestPyramidTicket;
         return true;
      }
      if(book.seedTicket == 0 || book.seedOpenTime <= 0)
      {
         Pyramid_CampaignReset(m_stats[dir]);
         m_statsAt[dir] = now;
         return false;
      }

      if(m_statsAt[dir] == now &&
         m_statsSeed[dir] == book.seedTicket &&
         m_statsSideCount[dir] == side.count &&
         MathAbs(m_statsSideLots[dir] - side.totalLots) <= 1e-12 &&
         m_statsNewestPyramid[dir] == book.newestPyramidTicket)
         return m_stats[dir].ready;

      SPyramidCampaignStats fresh;
      bool ok = Pyramid_ReadCampaignHistory(dir, book.seedOpenTime, now, fresh);
      m_stats[dir] = fresh;
      m_statsAt[dir] = now;
      m_statsSeed[dir] = book.seedTicket;
      m_statsSideCount[dir] = side.count;
      m_statsSideLots[dir] = side.totalLots;
      m_statsNewestPyramid[dir] = book.newestPyramidTicket;
      return ok && fresh.ready;
   }

   bool CampaignHistoryReady(const int dir) const
   {
      if(dir < BD_DIR_BUY || dir > BD_DIR_SELL) return false;
      return m_stats[dir].ready;
   }

   double CampaignRealized(const int dir) const
   {
      if(dir < BD_DIR_BUY || dir > BD_DIR_SELL || !m_stats[dir].ready) return 0.0;
      return m_stats[dir].realizedCash;
   }

   int CampaignAddCount(const int dir) const
   {
      if(dir < BD_DIR_BUY || dir > BD_DIR_SELL || !m_stats[dir].ready) return 0;
      return m_stats[dir].addCount;
   }

   bool EconomicTpLevel(const BasketSide &side, const int dir,
                        const double baseTp, double &economicTp) const
   {
      economicTp = baseTp;
      if(CorePyramidMode_ == pyramid_TAT || baseTp <= 0.0 || side.count <= 0)
         return true;
      if(dir < BD_DIR_BUY || dir > BD_DIR_SELL || !m_stats[dir].ready)
      {
         economicTp = 0.0;
         return false;
      }
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tickValue <= 0.0 || tickSize <= 0.0 || side.totalLots <= 0.0)
      {
         economicTp = 0.0;
         return false;
      }
      economicTp = Pyramid_AdjustTpLevelPure(dir, baseTp, m_stats[dir].realizedCash,
                                              side.totalLots, tickValue, tickSize);
      return true;
   }

   bool Drive(const EAContext &ctx, const BasketSide &side, const int dir,
              const int maxOrders, CRecoveryEngine *recovery,
              const bool allowAdd, const datetime lastBar, string &why)
   {
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
      // Risk-reducing Peel remains allowed before ADD-history readiness.
      if(!recoveryOwns && TryPeel(ctx, dir, book, why)) return true;
      if(recoveryOwns || !allowAdd || !CampaignHistoryReady(dir)) return false;
      return TryAdd(ctx, side, dir, maxOrders, lastBar, book, m_stats[dir], recovery, why);
   }
};

#endif // BD_CORE_PYRAMID_MQH
