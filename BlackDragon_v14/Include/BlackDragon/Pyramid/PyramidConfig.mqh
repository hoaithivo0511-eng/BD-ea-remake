//+------------------------------------------------------------------+
//| PyramidConfig.mqh — T17 nhồi dương Core + Recovery Hedge         |
//| 20 input đầy đủ, toàn bộ nhãn/giải thích hiển thị bằng tiếng Việt.|
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
input string PyramidLotSequence_ = "0.01-0.01-0.012-0.014"; // Chuỗi Lot nhồi dương; hết chuỗi lặp Lot cuối
input string PyramidMultiplierSequence_ = "1.0-1.2-1.15-1.1"; // Chuỗi hệ số nhân từ Lot gốc
input int PyramidMaxAdds_ = 4; // Số lệnh nhồi dương tối đa trong một phía Core
input double PyramidMaxTotalLots_ = 1.00; // Tổng Lot Core tối đa sau khi nhồi; 0 = chỉ theo MaxLot/MaxOrders
input double PyramidRiskBudgetPercent_ = 30.0; // Tối đa % lợi nhuận đang có được phép rủi ro cho lệnh nhồi mới
input double PyramidMinLockedProfitPips_ = 5.0; // Chỉ nhồi khi rổ đang lời tối thiểu số pip này tính từ hòa vốn
input int PyramidReserveDcaSlots_ = 3; // Luôn chừa tối thiểu số slot MaxOrders này cho DCA nếu thị trường đảo chiều
input double PyramidMinRoomToTPPips_ = 5.0; // Không nhồi nếu khoảng còn lại tới TP rổ nhỏ hơn số pip này
input double PyramidPeelGapPips_ = 7.0; // Giá hồi ngược từ lệnh Pyramid mới nhất bao nhiêu pip thì tháo LIFO
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
#define BD_PYRAMID_POLICY_REV 1
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

long Pyramid_HedgeStageTargetRawUnitsPure(const eRecoverySizingPolicy policy,
                                          const long coreUnits,
                                          const long existingBeforeGeneration,
                                          const double stageCoveragePercent)
{
   long desired = Recovery_T16PercentUnitsPure(coreUnits, stageCoveragePercent);
   if(desired <= 0) return 0;
   if(policy == ARCS_XEP_LOP) return desired;
   long existing = existingBeforeGeneration > 0 ? existingBeforeGeneration : 0;
   return desired > existing ? desired - existing : 0;
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

bool Pyramid_ValidateConfig(string &why)
{
   why = "";
   if(PyramidMaxAdds_ < 0 || PyramidMaxAdds_ > BD_PYRAMID_MAX_LEVELS)
   { why = "Số lệnh nhồi dương tối đa phải trong [0,32]"; return false; }
   if(PyramidMaxTotalLots_ < 0.0)
   { why = "Tổng Lot Core tối đa sau nhồi phải >= 0"; return false; }
   if(PyramidRiskBudgetPercent_ < 0.0 || PyramidRiskBudgetPercent_ > 100.0)
   { why = "Ngân sách lợi nhuận được phép rủi ro phải trong [0,100]%"; return false; }
   if(PyramidMinLockedProfitPips_ < 0.0 || PyramidMinRoomToTPPips_ < 0.0 || PyramidPeelGapPips_ < 0.0)
   { why = "Các ngưỡng pip của Pyramid Core phải >= 0"; return false; }
   if(PyramidReserveDcaSlots_ < 0)
   { why = "Số slot chừa cho DCA phải >= 0"; return false; }

   double tmp[];
   if(CorePyramidMode_ != pyramid_TAT)
   {
      if(!Pyramid_ParsePositiveSequence(PyramidDistanceSequence_, tmp))
      { why = "Chuỗi khoảng cách Pyramid Core không hợp lệ"; return false; }
      if(PyramidLotMode_ == pyramid_LOT_CHUOI && !Pyramid_ParsePositiveSequence(PyramidLotSequence_, tmp))
      { why = "Chuỗi Lot Pyramid Core không hợp lệ"; return false; }
      if(PyramidLotMode_ == pyramid_LOT_HE_SO && !Pyramid_ParsePositiveSequence(PyramidMultiplierSequence_, tmp))
      { why = "Chuỗi hệ số Pyramid Core không hợp lệ"; return false; }
   }

   if(HedgePyramidMaxCoveragePercent_ <= 0.0)
   { why = "Trần coverage Hedge Pyramid phải > 0"; return false; }
   if(HedgePyramidMinRoomToTPPips_ < 0.0)
   { why = "Khoảng tối thiểu tới TP Hedge phải >= 0"; return false; }
   if(HedgePyramidMode_ != hedge_pyramid_TAT)
   {
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
          "|coreMaxAdds=" + (string)PyramidMaxAdds_ +
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
