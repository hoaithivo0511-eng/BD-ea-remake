//+------------------------------------------------------------------+
//| CorePyramid.mqh — T17 Profit-Funded Core Pyramid + LIFO Peel     |
//| Pyramid dùng cùng Core Magic nhưng comment role BDP|... riêng.   |
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
   double nonPyramidLots;
   ulong seedTicket;
   datetime seedOpenTime;
};

void Pyramid_BookReset(SPyramidBook &b)
{
   ZeroMemory(b);
   b.highestLevel = 0;
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
      if(isP)
      {
         book.pyramidCount++;
         if(level > book.highestLevel) book.highestLevel = level;
         if(side.pos[i].openTime > book.newestPyramidTime ||
            (side.pos[i].openTime == book.newestPyramidTime &&
             side.pos[i].ticket > book.newestPyramidTicket))
         {
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

class CCorePyramidEngine
{
private:
   CExecutionLayer *m_exec;
   double m_distance[];
   double m_lots[];
   double m_mult[];
   ulong m_seedTicket[2];
   bool  m_campaignSeen[2];

   int CycleKey(const int dir) const { return 100 + dir; }

   double PipSize(const EAContext &ctx) const
   {
      return Recovery_PipSizePure(Sym_IsGold(), ctx.point, ctx.digits);
   }

   bool HistoryCampaignUsed(const int dir, const datetime seedOpenTime) const
   {
      if(seedOpenTime <= 0) return false;
      datetime from = seedOpenTime > 2 ? seedOpenTime - 2 : 0;
      if(!HistorySelect(from, TimeCurrent())) return false;
      long wantedType = dir == BD_DIR_BUY ? DEAL_TYPE_BUY : DEAL_TYPE_SELL;
      for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
      {
         ulong deal = HistoryDealGetTicket(i);
         if(deal == 0) continue;
         if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol ||
            HistoryDealGetInteger(deal, DEAL_MAGIC) != (long)Magic ||
            HistoryDealGetInteger(deal, DEAL_TYPE) != wantedType)
            continue;
         long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
         if(entry != DEAL_ENTRY_IN && entry != DEAL_ENTRY_INOUT) continue;
         string c = HistoryDealGetString(deal, DEAL_COMMENT);
         if(!Pyramid_IsComment(c)) continue;
         int cdir = Pyramid_CommentFieldInt(c, "D=");
         if(cdir == dir) return true;
      }
      return false;
   }

   void RefreshCampaignState(const int dir, const SPyramidBook &book)
   {
      if(dir < 0 || dir > 1) return;
      if(book.seedTicket == 0)
      {
         m_seedTicket[dir] = 0;
         m_campaignSeen[dir] = false;
         return;
      }
      if(m_seedTicket[dir] != book.seedTicket)
      {
         m_seedTicket[dir] = book.seedTicket;
         m_campaignSeen[dir] = HistoryCampaignUsed(dir, book.seedOpenTime);
      }
      if(book.pyramidCount > 0) m_campaignSeen[dir] = true;
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

   bool TryPeel(const EAContext &ctx, const int dir,
                const SPyramidBook &book, string &why)
   {
      if(book.pyramidCount <= 0 || book.newestPyramidTicket == 0) return false;
      double pip = PipSize(ctx);
      if(pip <= 0.0) return false;
      if(!Pyramid_PeelHitPure(dir, book.newestPyramidOpen, ctx.bid, ctx.ask,
                              PyramidPeelGapPips_ * pip)) return false;
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
         why = "LIFO Peel không gửi được lệnh đóng Pyramid #" + (string)book.newestPyramidTicket;
         return false;
      }
      why = "T17 LIFO Peel đóng Pyramid mới nhất ticket=" +
            (string)book.newestPyramidTicket;
      return true;
   }

   bool TryAdd(const EAContext &ctx, const BasketSide &side, const int dir,
               const int maxOrders, const SPyramidBook &book,
               CRecoveryEngine *recovery, string &why)
   {
      if(CorePyramidMode_ == pyramid_TAT || PyramidMaxAdds_ <= 0) return false;
      if(side.count <= 0 || book.nonPyramidCount != 1) return false;
      if(CorePyramidMode_ == pyramid_CHU_KY_SACH &&
         m_campaignSeen[dir] && book.pyramidCount == 0)
         return false;
      if(book.pyramidCount >= PyramidMaxAdds_) return false;
      if(side.count >= maxOrders) return false;
      if(PyramidReserveDcaSlots_ > 0 && side.count + 1 + PyramidReserveDcaSlots_ > maxOrders)
         return false;
      if(!RecoveryAllowsAdd(recovery, dir)) return false;
      if(m_exec.BusyOpen(dir) || m_exec.HasAnyPendingClose() ||
         m_exec.HasPendingForCycle(CycleKey(dir))) return false;
      if(!TrendAllows(ctx, dir)) return false;

      double pip = PipSize(ctx);
      if(pip <= 0.0) return false;
      double favorable = Pyramid_FavorablePipsPure(dir, side.breakeven,
                                                   ctx.bid, ctx.ask, pip);
      if(favorable + 1e-9 < PyramidMinLockedProfitPips_) return false;
      double room = Pyramid_RoomToTpPipsPure(dir, side.tpLevel,
                                             ctx.bid, ctx.ask, pip);
      if(room < PyramidMinRoomToTPPips_ - 1e-9) return false;

      int level = book.highestLevel + 1;
      if(level < 1) level = 1;
      double anchor = book.pyramidCount > 0 ? book.newestPyramidOpen : side.pos[0].openPrice;
      double gapPips = Pyramid_SeqValue(m_distance, level - 1);
      if(!Pyramid_FavorableGapHitPure(dir, anchor, ctx.bid, ctx.ask, gapPips * pip))
         return false;

      double candidate = ConfiguredLot(side, level);
      if(candidate <= 0.0) return false;

      double riskPerLot = RiskCashPerLot(ctx);
      double riskCap = Pyramid_RiskCapLotPure(MathMax(side.totalProfit, 0.0),
                                              PyramidRiskBudgetPercent_,
                                              riskPerLot);
      if(riskCap <= 0.0) return false;
      if(candidate > riskCap) candidate = riskCap;

      if(PyramidMaxTotalLots_ > 0.0)
      {
         double available = PyramidMaxTotalLots_ - side.totalLots;
         if(available <= 0.0) return false;
         if(candidate > available) candidate = available;
      }
      if(candidate > Cfg.MaxLot) candidate = Cfg.MaxLot;
      candidate = Pyramid_NormalizeFloor(candidate);
      if(candidate <= 0.0) return false;

      string comment = Pyramid_BuildComment(dir, level);
      if(!m_exec.OpenMarketOwned(dir, candidate, (long)Magic,
                                 CycleKey(dir),
                                 EXEC_CMD_CORE_PYRAMID_OPEN,
                                 EXEC_RECONCILE_FAIL_CLOSED,
                                 comment))
      {
         why = "Không gửi được lệnh nhồi dương Core level=" + (string)level;
         return false;
      }
      why = "T17 Pyramid Core mở level=" + (string)level +
            " lot=" + DoubleToString(candidate, 2) +
            " anchor=" + DoubleToString(anchor, ctx.digits);
      return true;
   }

public:
   CCorePyramidEngine(void)
   {
      m_exec = NULL;
      m_seedTicket[0] = m_seedTicket[1] = 0;
      m_campaignSeen[0] = m_campaignSeen[1] = false;
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

   void BuildDcaView(const BasketSide &source, BasketSide &out) const
   {
      Pyramid_BuildDcaView(source, out);
   }

   bool Drive(const EAContext &ctx, const BasketSide &side, const int dir,
              const int maxOrders, CRecoveryEngine *recovery, string &why)
   {
      why = "";
      if(CorePyramidMode_ == pyramid_TAT || side.count <= 0 || m_exec == NULL)
      {
         if(side.count <= 0 && dir >= 0 && dir <= 1)
         {
            m_seedTicket[dir] = 0;
            m_campaignSeen[dir] = false;
         }
         return false;
      }
      SPyramidBook book;
      Pyramid_ReadBook(side, book);
      RefreshCampaignState(dir, book);

      bool recoveryOwns = false;
      if(RecoveryMode_ == recovery_ACTIVE && recovery != NULL && recovery.ActiveReady())
      {
         SRecoveryCycle c;
         recovery.GetCycle(dir == BD_DIR_BUY ? recovery_CORE_BUY : recovery_CORE_SELL, c);
         recoveryOwns = c.state != recovery_CORE_ONLY;
      }
      if(!recoveryOwns && TryPeel(ctx, dir, book, why)) return true;
      if(recoveryOwns) return false;
      return TryAdd(ctx, side, dir, maxOrders, book, recovery, why);
   }
};

#endif // BD_CORE_PYRAMID_MQH
