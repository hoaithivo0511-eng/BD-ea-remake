//+------------------------------------------------------------------+
//| RecoveryT16Config.mqh — T16 ARCS stacked Recovery configuration |
//| New user-facing inputs use Vietnamese descriptions.              |
//| Existing T15 inputs remain source-compatible.                    |
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_T16_CONFIG_MQH
#define BD_RECOVERY_T16_CONFIG_MQH

#include "RecoveryTypes.mqh"

// T16.1: one durable slot per generation within one ARCS cycle. Closed slots
// are allowed to remain as tombstones until the cycle resets. Capacity is
// intentionally above the legacy input range (currently <=50).
#define BD_ARCS_MAX_LAYERS 64

enum eRecoverySizingPolicy
{
   HEDGE_CAN_BANG = 0, // Giữ tổng Hedge quanh tỷ lệ % của Core (tương thích kiến trúc cũ)
   ARCS_XEP_LOP   = 1  // Mỗi vòng mở một lớp Hedge mới theo % Core còn lại
};

enum eRecoverySLMode
{
   SL_BROKER  = 0, // Đặt SL thật tại broker
   SL_VIRTUAL = 1  // Không gửi SL; EA tự theo dõi và đóng lệnh khi chạm mức SL ảo
};

input group "18 — ARCS: KHỐI LƯỢNG HEDGE"
input eRecoverySizingPolicy RecoverySizingPolicy_ = ARCS_XEP_LOP; // Kiểu tính Hedge: cân bằng hoặc xếp lớp ARCS
input double HedgeVolumePercent_ = 100.0; // Tỷ lệ khối lượng Hedge so với Core hiện tại (%); có thể <100 hoặc >100

input group "19 — ARCS: SL & KHÓA LỢI NHUẬN"
input eRecoverySLMode HedgeSLMode_ = SL_BROKER; // Chế độ SL Hedge: broker hoặc SL ảo do EA quản lý

input group "20 — ARCS: GLOBAL SL / CHUYỂN PHA"
input bool   EnableGlobalHedgeSL_          = true; // Bật Global SL cho toàn bộ lớp Hedge sau nhiều vòng
input int    GlobalSLAfterGenerations_     = 5;    // Sau bao nhiêu thế hệ Hedge thì chuyển sang Global SL
input double GlobalHedgeSLNetProfitPips_   = 3.0;  // Lợi nhuận ròng tối thiểu muốn khóa cho từng lớp tại Global SL (pip)
input double RecoveryReentryBufferPips_    = 10.0; // Buffer xác nhận tái kích hoạt Recovery sau khi Global SL khớp (pip)

bool Recovery_T16SizingPolicyValid(const eRecoverySizingPolicy policy)
{
   return policy == HEDGE_CAN_BANG || policy == ARCS_XEP_LOP;
}

bool Recovery_T16SlModeValid(const eRecoverySLMode mode)
{
   return mode == SL_BROKER || mode == SL_VIRTUAL;
}

long Recovery_T16PercentUnitsPure(const long coreUnits,
                                  const double hedgePercent)
{
   if(coreUnits <= 0 || hedgePercent <= 0.0) return 0;
   return (long)MathFloor((double)coreUnits * hedgePercent / 100.0 + 1e-9);
}

long Recovery_T16NewGenerationUnitsPure(const eRecoverySizingPolicy policy,
                                        const long coreUnits,
                                        const long existingHedgeUnits,
                                        const double hedgePercent)
{
   long desired = Recovery_T16PercentUnitsPure(coreUnits, hedgePercent);
   if(desired <= 0) return 0;
   if(policy == ARCS_XEP_LOP) return desired;
   long existing = existingHedgeUnits > 0 ? existingHedgeUnits : 0;
   return desired > existing ? desired - existing : 0;
}

bool Recovery_T16VirtualSlHitPure(const eRecoveryCoreDirection coreDir,
                                  const double bid,
                                  const double ask,
                                  const double slPrice)
{
   if(bid <= 0.0 || ask <= 0.0 || slPrice <= 0.0) return false;
   if(coreDir == recovery_CORE_BUY) return ask >= slPrice;
   return bid <= slPrice;
}

bool Recovery_T16VirtualSlArmingValidPure(const eRecoveryCoreDirection coreDir,
                                          const double bid,
                                          const double ask,
                                          const double slPrice)
{
   if(bid <= 0.0 || ask <= 0.0 || slPrice <= 0.0) return false;
   if(coreDir == recovery_CORE_BUY) return slPrice > ask;
   return slPrice < bid;
}

double Recovery_T16GlobalSlFoldPure(const eRecoveryCoreDirection coreDir,
                                    const double accumulated,
                                    const double candidate)
{
   if(candidate <= 0.0) return accumulated;
   if(accumulated <= 0.0) return candidate;
   return coreDir == recovery_CORE_BUY ? MathMin(accumulated, candidate)
                                       : MathMax(accumulated, candidate);
}

uint Recovery_T16SemanticFingerprint()
{
   string canonical =
      "base=" + (string)Recovery_CurrentSemanticConfigFingerprint() +
      "|sizing=" + (string)(int)RecoverySizingPolicy_ +
      "|hedgePct=" + DoubleToString(HedgeVolumePercent_, 12) +
      "|slMode=" + (string)(int)HedgeSLMode_ +
      "|globalEnable=" + (EnableGlobalHedgeSL_ ? "1" : "0") +
      "|globalAfter=" + (string)GlobalSLAfterGenerations_ +
      "|globalProfit=" + DoubleToString(GlobalHedgeSLNetProfitPips_, 12) +
      "|reentryBuffer=" + DoubleToString(RecoveryReentryBufferPips_, 12) +
      "|layerCapacity=" + (string)BD_ARCS_MAX_LAYERS;
   return Recovery_Fnv1aTextPure(canonical);
}

bool Recovery_T16ValidateConfig(string &why)
{
   why = "";
   if(RecoveryMode_ == recovery_OFF) return true;
   if(!Recovery_T16SizingPolicyValid(RecoverySizingPolicy_))
   {
      why = "Kiểu xử lý Hedge không hợp lệ";
      return false;
   }
   if(HedgeVolumePercent_ <= 0.0)
   {
      why = "Tỷ lệ khối lượng Hedge (%) phải > 0";
      return false;
   }
   if(!Recovery_T16SlModeValid(HedgeSLMode_))
   {
      why = "Chế độ SL Hedge không hợp lệ";
      return false;
   }
   if(MaxHedgeGenerations_ > BD_ARCS_MAX_LAYERS)
   {
      why = "Số vòng Hedge tối đa vượt capacity ARCS=" + (string)BD_ARCS_MAX_LAYERS;
      return false;
   }
   if(EnableGlobalHedgeSL_)
   {
      if(GlobalSLAfterGenerations_ < 1)
      {
         why = "Số vòng kích hoạt Global SL phải >= 1 khi bật Global SL";
         return false;
      }
      if(GlobalSLAfterGenerations_ > MaxHedgeGenerations_)
      {
         why = "Số vòng kích hoạt Global SL không được lớn hơn Số vòng Hedge tối đa";
         return false;
      }
      if(GlobalHedgeSLNetProfitPips_ < 0.0)
      {
         why = "Lợi nhuận tối thiểu Global SL phải >= 0 pip";
         return false;
      }
      if(RecoveryReentryBufferPips_ < 0.0)
      {
         why = "Buffer tái kích hoạt Recovery phải >= 0 pip";
         return false;
      }
   }
   return true;
}

bool Recovery_T16UseStackEngine()
{
   if(RecoverySizingPolicy_ == ARCS_XEP_LOP) return true;
   if(MathAbs(HedgeVolumePercent_ - 100.0) > 1e-12) return true;
   if(HedgeSLMode_ == SL_VIRTUAL) return true;
   if(EnableGlobalHedgeSL_) return true;
   return false;
}

#endif // BD_RECOVERY_T16_CONFIG_MQH
