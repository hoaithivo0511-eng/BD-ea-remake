//+------------------------------------------------------------------+
//| PyramidConfig.mqh — T17.3 Core/Hedge Pyramid policy              |
//| Serial re-arm giữ campaign ledger nhưng không giữ price extreme. |
//+------------------------------------------------------------------+
#ifndef BD_PYRAMID_CONFIG_MQH
#define BD_PYRAMID_CONFIG_MQH

#include <BlackDragon/GridEngine.mqh>

enum eCorePyramidMode
{
   pyramid_TAT = 0,
   pyramid_CHU_KY_SACH = 1,
   pyramid_TAI_KICH_HOAT = 2
};

enum ePyramidLotMode
{
   pyramid_LOT_CHUOI = 0,
   pyramid_LOT_HE_SO = 1,
   pyramid_LOT_RUI_RO = 2
};

enum eHedgePyramidMode
{
   hedge_pyramid_TAT = 0,
   hedge_pyramid_BAC_COVERAGE = 1
};

input group "23 — NHỒI DƯƠNG LỆNH CHÍNH (PYRAMID CORE)"
input eCorePyramidMode CorePyramidMode_ = pyramid_TAT; // Chế độ nhồi dương lệnh chính
input string PyramidDistanceSequence_ = "10x2-15-20"; // Khoảng giá thuận chiều giữa các lần nhồi (pip)
input ePyramidLotMode PyramidLotMode_ = pyramid_LOT_HE_SO; // Cách tính Lot nhồi dương
input string PyramidLotSequence_ = "0.01-0.01-0.012-0.014"; // Chuỗi Lot cố định; hết chuỗi lặp Lot cuối
input string PyramidMultiplierSequence_ = "1.0-1.2-1.15-1.1"; // Chuỗi hệ số nhân từ Lot gốc
input int PyramidMaxAdds_ = 4; // Số lệnh Pyramid Core được phép mở đồng thời; 0 = không ADD
input double PyramidMaxTotalLots_ = 1.00; // Tổng Lot Core tối đa sau khi nhồi; 0 = tắt giới hạn này
input double PyramidRiskBudgetPercent_ = 30.0; // % lợi nhuận kinh tế dùng làm risk cap; 0 = tắt (không áp cho Lot chuỗi cố định)
input double PyramidMinLockedProfitPips_ = 5.0; // Lợi nhuận kinh tế campaign tối thiểu quy đổi pip; 0 = tắt
input int PyramidReserveDcaSlots_ = 3; // Chừa slot MaxOrders cho DCA; 0 = không chừa chủ động
input double PyramidMinRoomToTPPips_ = 5.0; // Khoảng tối thiểu còn lại tới TP; 0 = tắt điều kiện
input double PyramidPeelGapPips_ = 7.0; // Giá hồi ngược từ Pyramid mới nhất bao nhiêu pip thì tháo LIFO
input bool PyramidRequireTrend_ = true; // Yêu cầu không có tín hiệu đối nghịch tại thời điểm nhồi

input group "24 — NHỒI DƯƠNG RECOVERY HEDGE"
input eHedgePyramidMode HedgePyramidMode_ = hedge_pyramid_TAT; // Chế độ tăng dần khối lượng Hedge khi Hedge đang thắng
input string HedgePyramidCoverageSequence_ = "35-55-75-100"; // Các bậc tỷ lệ Hedge/Core mục tiêu (%)
input string HedgePyramidGapSequence_ = "10-10-15"; // Khoảng thuận chiều của Hedge để lên bậc tiếp theo (pip)
input double HedgePyramidMaxCoveragePercent_ = 100.0; // Trần coverage tuyệt đối; không bao giờ vượt mức này
input bool HedgePyramidReserveFullTarget_ = true; // Trước bậc đầu, yêu cầu Free Margin đủ cho target cuối dự kiến
input double HedgePyramidMinRoomToTPPips_ = 5.0; // Không tăng Hedge nếu target TP dự kiến còn quá gần
input bool HedgePyramidLockBeforeAdd_ = true; // Chỉ tăng bậc khi phần Hedge đang có đã ở phía lợi nhuận ròng

#define BD_PYRAMID_COMMENT_PREFIX "BDP|"
#define BD_PYRAMID_POLICY_REV 4
#define BD_PYRAMID_MAX_LEVELS 32

bool Pyramid_IsComment(const string comment)
{
   return StringFind(comment, BD_PYRAMID_COMMENT_PREFIX) == 0;
}

int Pyramid_CommentFieldInt(const string comment, const string key)
{
   int p = StringFind(comment, key);
   if(p < 0) return -1;
   int start = p + StringLen(key);
   int stop = StringFind(comment, "|", start);
   string token = stop < 0 ? StringSubstr(comment, start)
                           : StringSubstr(comment, start, stop - start);
   if(token == "") return -1;
   return (int)StringToInteger(token);
}

int Pyramid_LevelFromComment(const string comment)
{
   if(!Pyramid_IsComment(comment)) return -1;
   return Pyramid_CommentFieldInt(comment, "L=");
}

string Pyramid_BuildComment(const int dir, const int level)
{
   return "BDP|D=" + (string)dir + "|L=" + (string)level + "|R=" + (string)BD_PYRAMID_POLICY_REV;
}

bool Pyramid_ParsePositiveSequence(const string seq, double &values[])
{
   return Grid_ParseLotSequence(seq, values) > 0;
}

double Pyramid_SeqValue(const double &values[], const int index)
{
   int n = ArraySize(values);
   if(n <= 0) return 0.0;
   int i = index < 0 ? 0 : index;
   if(i >= n) i = n - 1;
   return values[i];
}

bool Pyramid_FavorableGapHitPure(const int dir,
                                 const double anchor,
                                 const double bid,
                                 const double ask,
                                 const double gapPrice)
{
   if(anchor <= 0.0 || bid <= 0.0 || ask <= 0.0 || gapPrice < 0.0) return false;
   return dir == 0 ? ask >= anchor + gapPrice
                   : bid <= anchor - gapPrice;
}

bool Pyramid_PeelHitPure(const int dir,
                         const double newestOpen,
                         const double bid,
                         const double ask,
                         const double peelPrice)
{
   if(newestOpen <= 0.0 || bid <= 0.0 || ask <= 0.0 || peelPrice < 0.0) return false;
   return dir == 0 ? bid <= newestOpen - peelPrice
                   : ask >= newestOpen + peelPrice;
}

double Pyramid_FavorablePipsPure(const int dir,
                                 const double breakeven,
                                 const double bid,
                                 const double ask,
                                 const double pipSize)
{
   if(breakeven <= 0.0 || pipSize <= 0.0) return 0.0;
   double px = dir == 0 ? bid : ask;
   double d = dir == 0 ? px - breakeven : breakeven - px;
   return d / pipSize;
}

double Pyramid_RoomToTpPipsPure(const int dir,
                                const double tpLevel,
                                const double bid,
                                const double ask,
                                const double pipSize)
{
   if(tpLevel <= 0.0 || pipSize <= 0.0) return DBL_MAX;
   double room = dir == 0 ? tpLevel - ask : bid - tpLevel;
   return room / pipSize;
}

double Pyramid_RiskCapLotPure(const double positiveFloatingCash,
                              const double budgetPercent,
                              const double riskCashPerLot)
{
   if(positiveFloatingCash <= 0.0 || budgetPercent <= 0.0 || riskCashPerLot <= 0.0) return 0.0;
   double pct = budgetPercent > 100.0 ? 100.0 : budgetPercent;
   return positiveFloatingCash * pct / 100.0 / riskCashPerLot;
}

double Pyramid_AvailableRiskCashPure(const double floatingCash,
                                     const double realizedPyramidCash,
                                     const double openPyramidRiskCash,
                                     const double budgetPercent)
{
   if(budgetPercent <= 0.0) return 0.0;
   double pct = budgetPercent > 100.0 ? 100.0 : budgetPercent;
   double economic = floatingCash + realizedPyramidCash;
   if(economic <= 0.0) return 0.0;
   double allowed = economic * pct / 100.0;
   double used = MathMax(openPyramidRiskCash, 0.0);
   return MathMax(allowed - used, 0.0);
}

int Pyramid_NextSerialLevelPure(const int highestHistoricalLevel)
{
   return highestHistoricalLevel < 1 ? 1 : highestHistoricalLevel + 1;
}

// Compatibility alias for older T17 callers/tests.
int Pyramid_NextCampaignLevelPure(const int highestHistoricalLevel)
{
   return Pyramid_NextSerialLevelPure(highestHistoricalLevel);
}

bool Pyramid_ConcurrentAddAllowedPure(const int openPyramidCount, const int maxAdds)
{
   return maxAdds > 0 && openPyramidCount >= 0 && openPyramidCount < maxAdds;
}

// Compatibility oracle only; runtime no longer uses lifetime add count as cap.
bool Pyramid_CumulativeAddAllowedPure(const int cumulativeAdds, const int maxAdds)
{
   return maxAdds > 0 && cumulativeAdds >= 0 && cumulativeAdds < maxAdds;
}

double Pyramid_RearmAnchorPure(const double newestLivePyramidOpen,
                               const double basketBreakeven)
{
   return newestLivePyramidOpen > 0.0 ? newestLivePyramidOpen : basketBreakeven;
}

// T17.3 anchor precedence:
// 1) a newer non-Pyramid Core add (Seed/DCA epoch) resets spacing to current BE;
// 2) otherwise the latest Pyramid exit is a TEMPORARY post-Peel re-arm anchor;
// 3) after a later Pyramid add succeeds, newest live fill resumes as anchor.
// No historical favorable extreme is retained.
double Pyramid_T173RearmAnchorPure(const double newestLivePyramidOpen,
                                   const double basketBreakeven,
                                   const long newestNonPyramidTimeMsc,
                                   const long lastPyramidAddTimeMsc,
                                   const long lastPyramidExitTimeMsc,
                                   const double lastPyramidExitPrice)
{
   if(newestNonPyramidTimeMsc > lastPyramidAddTimeMsc && basketBreakeven > 0.0)
      return basketBreakeven;
   if(lastPyramidExitTimeMsc > lastPyramidAddTimeMsc && lastPyramidExitPrice > 0.0)
      return lastPyramidExitPrice;
   return Pyramid_RearmAnchorPure(newestLivePyramidOpen, basketBreakeven);
}

bool Pyramid_AddTimingAllowsPure(const datetime lastAddTime,
                                 const datetime lastAddBar,
                                 const datetime now,
                                 const datetime barTime,
                                 const int minuteStop)
{
   if(barTime > 0 && lastAddBar == barTime) return false;
   if(minuteStop > 0 && lastAddTime > 0 && now <= lastAddTime + minuteStop * 60)
      return false;
   return true;
}

// ADD may not follow ANY Pyramid ADD/Peel mutation in the same bar. A Peel
// itself is never blocked by this helper because risk reduction stays urgent.
bool Pyramid_T173AddAfterMutationAllowsPure(const datetime lastMutationTime,
                                             const datetime now,
                                             const datetime barTime,
                                             const int minuteStop)
{
   if(barTime > 0 && lastMutationTime >= barTime) return false;
   if(minuteStop > 0 && lastMutationTime > 0 &&
      now <= lastMutationTime + minuteStop * 60)
      return false;
   return true;
}

bool Pyramid_RiskBudgetAppliesPure(const ePyramidLotMode mode,
                                   const double budgetPercent)
{
   return mode != pyramid_LOT_CHUOI && budgetPercent > 0.0;
}

bool Pyramid_RiskModeReadyPure(const ePyramidLotMode mode,
                               const double budgetPercent)
{
   return mode != pyramid_LOT_RUI_RO || budgetPercent > 0.0;
}

double Pyramid_CampaignEconomicProfitPure(const double floatingCash,
                                          const double realizedPyramidCash)
{
   return floatingCash + realizedPyramidCash;
}

double Pyramid_PipsCashPure(const double pips,
                            const double totalLots,
                            const double tickValue,
                            const double tickSize,
                            const double pipSize)
{
   if(pips <= 0.0 || totalLots <= 0.0 || tickValue <= 0.0 ||
      tickSize <= 0.0 || pipSize <= 0.0)
      return 0.0;
   return pips * pipSize / tickSize * tickValue * totalLots;
}

bool Pyramid_EconomicMinLockedAllowsPure(const double floatingCash,
                                         const double realizedPyramidCash,
                                         const double minLockedPips,
                                         const double totalLots,
                                         const double tickValue,
                                         const double tickSize,
                                         const double pipSize)
{
   if(minLockedPips <= 0.0) return true;
   double need = Pyramid_PipsCashPure(minLockedPips, totalLots,
                                      tickValue, tickSize, pipSize);
   if(need <= 0.0) return false;
   return Pyramid_CampaignEconomicProfitPure(floatingCash, realizedPyramidCash) + 1e-9 >= need;
}

bool Pyramid_DcaPriorityReleaseNeededPure(const bool dcaDue,
                                          const int totalOpenCount,
                                          const int maxOrders,
                                          const int openPyramidCount)
{
   return dcaDue && maxOrders > 0 && totalOpenCount >= maxOrders && openPyramidCount > 0;
}

double Pyramid_TpRecoveryShiftPure(const double realizedPyramidCash,
                                   const double totalLots,
                                   const double tickValue,
                                   const double tickSize)
{
   if(realizedPyramidCash >= 0.0 || totalLots <= 0.0 || tickValue <= 0.0 || tickSize <= 0.0)
      return 0.0;
   return (-realizedPyramidCash) / (tickValue * totalLots) * tickSize;
}

double Pyramid_AdjustTpLevelPure(const int dir,
                                 const double baseTp,
                                 const double realizedPyramidCash,
                                 const double totalLots,
                                 const double tickValue,
                                 const double tickSize)
{
   if(baseTp <= 0.0) return baseTp;
   double shift = Pyramid_TpRecoveryShiftPure(realizedPyramidCash, totalLots,
                                              tickValue, tickSize);
   return dir == 0 ? baseTp + shift : baseTp - shift;
}

double Pyramid_EffectiveCoveragePure(const double stageCoverage,
                                     const double hedgeVolumePercent,
                                     const double hardMaxCoverage)
{
   double v = stageCoverage;
   if(hedgeVolumePercent > 0.0 && v > hedgeVolumePercent) v = hedgeVolumePercent;
   if(hardMaxCoverage > 0.0 && v > hardMaxCoverage) v = hardMaxCoverage;
   return v > 0.0 ? v : 0.0;
}

bool Pyramid_CoreModeValid(const eCorePyramidMode mode)
{
   return mode == pyramid_TAT || mode == pyramid_CHU_KY_SACH ||
          mode == pyramid_TAI_KICH_HOAT;
}

bool Pyramid_LotModeValid(const ePyramidLotMode mode)
{
   return mode == pyramid_LOT_CHUOI || mode == pyramid_LOT_HE_SO ||
          mode == pyramid_LOT_RUI_RO;
}

bool Pyramid_HedgeModeValid(const eHedgePyramidMode mode)
{
   return mode == hedge_pyramid_TAT || mode == hedge_pyramid_BAC_COVERAGE;
}

bool Pyramid_ValidateConfig(string &why)
{
   why = "";
   if(!Pyramid_CoreModeValid(CorePyramidMode_))
   { why = "Chế độ Pyramid Core không hợp lệ"; return false; }
   if(!Pyramid_HedgeModeValid(HedgePyramidMode_))
   { why = "Chế độ Pyramid Hedge không hợp lệ"; return false; }

   if(CorePyramidMode_ != pyramid_TAT)
   {
      if(!Pyramid_LotModeValid(PyramidLotMode_))
      { why = "Cách tính Lot Pyramid Core không hợp lệ"; return false; }
      if(PyramidMaxAdds_ < 0)
      { why = "Số Pyramid Core mở đồng thời tối đa phải >= 0"; return false; }
      if(PyramidMaxTotalLots_ < 0.0)
      { why = "Tổng Lot Core tối đa sau nhồi phải >= 0"; return false; }
      if(PyramidRiskBudgetPercent_ < 0.0 || PyramidRiskBudgetPercent_ > 100.0)
      { why = "Ngân sách lợi nhuận được phép rủi ro phải trong [0,100]%"; return false; }
      if(PyramidMinLockedProfitPips_ < 0.0 || PyramidMinRoomToTPPips_ < 0.0)
      { why = "Các ngưỡng lợi nhuận/TP của Pyramid Core phải >= 0"; return false; }
      if(PyramidPeelGapPips_ <= 0.0)
      { why = "Bật Pyramid Core thì khoảng Peel LIFO phải > 0 pip"; return false; }
      if(PyramidReserveDcaSlots_ < 0)
      { why = "Số slot chừa cho DCA phải >= 0"; return false; }

      double tmp[];
      if(!Pyramid_ParsePositiveSequence(PyramidDistanceSequence_, tmp))
      { why = "Chuỗi khoảng cách Pyramid Core không hợp lệ"; return false; }
      if(PyramidLotMode_ == pyramid_LOT_CHUOI && !Pyramid_ParsePositiveSequence(PyramidLotSequence_, tmp))
      { why = "Chuỗi Lot Pyramid Core không hợp lệ"; return false; }
      if(PyramidLotMode_ == pyramid_LOT_HE_SO && !Pyramid_ParsePositiveSequence(PyramidMultiplierSequence_, tmp))
      { why = "Chuỗi hệ số Pyramid Core không hợp lệ"; return false; }
   }

   if(HedgePyramidMode_ != hedge_pyramid_TAT)
   {
      if(HedgePyramidMaxCoveragePercent_ <= 0.0)
      { why = "Trần coverage Hedge Pyramid phải > 0"; return false; }
      if(HedgePyramidMinRoomToTPPips_ < 0.0)
      { why = "Khoảng tối thiểu tới TP Hedge phải >= 0"; return false; }

      double cov[];
      double gaps[];
      if(!Pyramid_ParsePositiveSequence(HedgePyramidCoverageSequence_, cov))
      { why = "Chuỗi coverage Hedge Pyramid không hợp lệ"; return false; }
      if(ArraySize(cov) > BD_PYRAMID_MAX_LEVELS)
      { why = "Chuỗi coverage Hedge Pyramid vượt 32 bậc"; return false; }
      for(int i = 1; i < ArraySize(cov); i++)
         if(cov[i] <= cov[i-1])
         { why = "Chuỗi coverage Hedge Pyramid phải tăng dần nghiêm ngặt"; return false; }
      if(ArraySize(cov) > 1 && !Pyramid_ParsePositiveSequence(HedgePyramidGapSequence_, gaps))
      { why = "Chuỗi khoảng cách Hedge Pyramid không hợp lệ"; return false; }
   }
   return true;
}

string Pyramid_SemanticText()
{
   return "pyrRev=" + (string)BD_PYRAMID_POLICY_REV +
          "|coreMode=" + (string)(int)CorePyramidMode_ +
          "|coreDist=" + PyramidDistanceSequence_ +
          "|coreLotMode=" + (string)(int)PyramidLotMode_ +
          "|coreLotSeq=" + PyramidLotSequence_ +
          "|coreMulSeq=" + PyramidMultiplierSequence_ +
          "|coreMaxConcurrent=" + (string)PyramidMaxAdds_ +
          "|coreMaxLots=" + DoubleToString(PyramidMaxTotalLots_, 12) +
          "|coreRiskPct=" + DoubleToString(PyramidRiskBudgetPercent_, 12) +
          "|coreMinLock=" + DoubleToString(PyramidMinLockedProfitPips_, 12) +
          "|coreReserveDca=" + (string)PyramidReserveDcaSlots_ +
          "|coreRoomTp=" + DoubleToString(PyramidMinRoomToTPPips_, 12) +
          "|corePeel=" + DoubleToString(PyramidPeelGapPips_, 12) +
          "|coreTrend=" + (PyramidRequireTrend_ ? "1" : "0") +
          "|hedgeMode=" + (string)(int)HedgePyramidMode_ +
          "|hedgeCov=" + HedgePyramidCoverageSequence_ +
          "|hedgeGap=" + HedgePyramidGapSequence_ +
          "|hedgeMaxCov=" + DoubleToString(HedgePyramidMaxCoveragePercent_, 12) +
          "|hedgeReserve=" + (HedgePyramidReserveFullTarget_ ? "1" : "0") +
          "|hedgeRoomTp=" + DoubleToString(HedgePyramidMinRoomToTPPips_, 12) +
          "|hedgeLockAdd=" + (HedgePyramidLockBeforeAdd_ ? "1" : "0");
}

#endif // BD_PYRAMID_CONFIG_MQH
