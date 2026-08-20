//+------------------------------------------------------------------+
//| RecoveryT16Config.mqh — T16.6 ARCS Recovery configuration       |
//| Vietnamese-facing inputs + sizing / broker-min policy helpers.   |
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_T16_CONFIG_MQH
#define BD_RECOVERY_T16_CONFIG_MQH

#include "RecoveryTypes.mqh"
#include "RecoveryT164Reachability.mqh"

#define BD_ARCS_MAX_LAYERS 64
#define BD_ARCS_MIN_VOLUME_POLICY_REV 1

enum eRecoverySizingPolicy
{
   HEDGE_CAN_BANG = 0,
   ARCS_XEP_LOP   = 1
};

enum eRecoverySLMode
{
   SL_BROKER  = 0,
   SL_VIRTUAL = 1
};

enum eRecoveryModifyDisposition
{
   RECOVERY_MODIFY_ACCEPTED = 0,
   RECOVERY_MODIFY_DEFER_NO_EFFECT,
   RECOVERY_MODIFY_RECONCILE
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

input group "21 — ARCS: OVERLAP SAU KHI HEDGE"
input bool OverlapAfterHedge_ = false; // true: vẫn tỉa Overlap Core khi Recovery đã Hedge; ARCS refresh Core/Hedge trước bước kế tiếp

input group "22 — ARCS: AN TOÀN MARGIN & NHẬT KÝ"
input bool RecoveryDcaMarginReserve_ = true; // true: trước DCA Core, giữ đủ margin ước tính cho DCA + thế hệ Hedge kế tiếp
input int  RecoveryWaitLogSeconds_   = 900;  // Chu kỳ heartbeat log khi Recovery chỉ đang CHỜ (giây); 0 = chỉ log lần đầu mỗi key

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

// Mathematical sizing remains separately testable and broker-independent.
long Recovery_T16NewGenerationRawUnitsPure(const eRecoverySizingPolicy policy,
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

// T16.6 owner policy: a positive Hedge generation smaller than broker minimum
// becomes exactly the broker minimum. Zero stays zero; no Hedge is invented.
long Recovery_T166ClampPositiveGenerationUnitsPure(const long rawUnits,
                                                   const long minUnits)
{
   if(rawUnits <= 0) return 0;
   if(minUnits <= 0) return rawUnits;
   return rawUnits < minUnits ? minUnits : rawUnits;
}

long Recovery_T16CurrentBrokerMinUnits()
{
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minVolume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(step <= 0.0 || minVolume <= 0.0) return 0;
   return Recovery_VolumeToUnitsCeil(minVolume, step);
}

// Compatibility entry point used throughout the ARCS runtime. T16.6 applies
// the broker execution floor here so StartGeneration, post-Overlap sizing and
// the T16.5 DCA margin reserve all consume the same executable target.
long Recovery_T16NewGenerationUnitsPure(const eRecoverySizingPolicy policy,
                                        const long coreUnits,
                                        const long existingHedgeUnits,
                                        const double hedgePercent)
{
   long raw = Recovery_T16NewGenerationRawUnitsPure(policy,
                                                    coreUnits,
                                                    existingHedgeUnits,
                                                    hedgePercent);
   if(raw <= 0) return 0;

   long minUnits = Recovery_T16CurrentBrokerMinUnits();
   long planned = Recovery_T166ClampPositiveGenerationUnitsPure(raw, minUnits);
   if(planned > raw)
   {
      // This helper can be evaluated repeatedly by reserve/planning paths.
      // Suppress duplicate evidence for the same raw/planned pair.
      static long lastRaw = -1;
      static long lastPlanned = -1;
      if(lastRaw != raw || lastPlanned != planned)
      {
         double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
         Print("[BD:Recovery] INFO T16.6 Hedge target clamped to broker minimum raw=",
               DoubleToString(Recovery_UnitsToVolume(raw, step), 8),
               " planned=",
               DoubleToString(Recovery_UnitsToVolume(planned, step), 8));
         lastRaw = raw;
         lastPlanned = planned;
      }
   }
   return planned;
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

eRecoveryModifyDisposition Recovery_T162ModifyDispositionPure(const bool requestAccepted,
                                                               const bool outcomeAmbiguous)
{
   if(requestAccepted) return RECOVERY_MODIFY_ACCEPTED;
   if(outcomeAmbiguous) return RECOVERY_MODIFY_RECONCILE;
   return RECOVERY_MODIFY_DEFER_NO_EFFECT;
}

long Recovery_T162PostOverlapGenerationUnitsPure(const eRecoverySizingPolicy policy,
                                                 const long refreshedCoreUnits,
                                                 const long refreshedHedgeUnits,
                                                 const double hedgePercent)
{
   return Recovery_T16NewGenerationUnitsPure(policy,
                                             refreshedCoreUnits,
                                             refreshedHedgeUnits,
                                             hedgePercent);
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
      "|overlapAfterHedge=" + (OverlapAfterHedge_ ? "1" : "0") +
      "|dcaMarginReserve=" + (RecoveryDcaMarginReserve_ ? "1" : "0") +
      "|minVolumePolicyRev=" + (string)BD_ARCS_MIN_VOLUME_POLICY_REV +
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
   if(RecoveryWaitLogSeconds_ < 0 || RecoveryWaitLogSeconds_ > 86400)
   {
      why = "Chu kỳ heartbeat log Recovery phải trong [0,86400] giây";
      return false;
   }

   if(!Recovery_T164ValidateReachability(RecoveryMode_,
                                         Flag_Trade_Buy_, Flag_Trade_Sell_,
                                         MaxOrdersBuy, MaxOrdersSell,
                                         RecoveryStartAfterDca_, why))
      return false;

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
   if(RecoveryMode_ == recovery_ACTIVE &&
      !Recovery_T164ValidateReachabilityPure(RecoveryMode_,
                                             Flag_Trade_Buy_, Flag_Trade_Sell_,
                                             MaxOrdersBuy, MaxOrdersSell,
                                             RecoveryStartAfterDca_))
      return true;

   if(RecoverySizingPolicy_ == ARCS_XEP_LOP) return true;
   if(MathAbs(HedgeVolumePercent_ - 100.0) > 1e-12) return true;
   if(HedgeSLMode_ == SL_VIRTUAL) return true;
   if(EnableGlobalHedgeSL_) return true;
   if(OverlapAfterHedge_) return true;
   // T16.5 margin reserve is a Strategy preflight and MUST NOT force a
   // compatibility/legacy Recovery configuration into the ARCS engine.
   return false;
}

#endif // BD_RECOVERY_T16_CONFIG_MQH
