//+------------------------------------------------------------------+
//| RecoveryTypes.mqh — Adaptive Recovery Hedge foundation           |
//| Purpose   : Recovery mode/state/config types + init guards.      |
//| Invariants: Types/config only; no trade API calls.               |
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_TYPES_MQH
#define BD_RECOVERY_TYPES_MQH

#include <BlackDragon/Config.mqh>
#include "RecoveryMath.mqh"

enum eRecoveryMode
{
   recovery_OFF    = 0, // TẮT — không chạy Recovery
   recovery_SHADOW = 1, // QUAN SÁT — chỉ tính/log, không gửi lệnh Recovery
   recovery_ACTIVE = 2  // HOẠT ĐỘNG — thực thi Recovery Hedge
};

enum eRecoveryCoreDirection
{
   recovery_CORE_BUY  = 0,
   recovery_CORE_SELL = 1
};

enum eRecoveryCoreCloseMode
{
   recovery_Oldest   = 0, // Cũ nhất — ưu tiên lệnh Core mở sớm nhất
   recovery_Newest   = 1, // Mới nhất — ưu tiên lệnh Core mở gần nhất
   recovery_Lossiest = 2, // Lỗ nặng nhất — theo mức lỗ trên mỗi đơn vị khối lượng
   recovery_ProRata  = 3  // Theo tỷ lệ — phân bổ đóng đều theo tỷ trọng
};

enum eRecoveryState
{
   recovery_CORE_ONLY = 0,
   recovery_ARMED,
   recovery_HEDGE_BUILDING,
   recovery_HEDGE_ACTIVE,
   recovery_HEDGE_TP_PENDING,
   recovery_CORE_CLOSE_PENDING,
   recovery_HEDGE_LOCK_PENDING,
   recovery_HEDGE_LOCKED,
   recovery_REHEDGE_PENDING,
   recovery_PAUSE_SOFT,
   recovery_PAUSE_HARD,
   recovery_RECONCILE_REQUIRED,
   recovery_GLOBAL_STOP,
   recovery_COMPLETED
};

enum eRecoveryShadowDecision
{
   recovery_SHADOW_NONE = 0,
   recovery_SHADOW_WOULD_OPEN_HEDGE,
   recovery_SHADOW_HEDGE_PLAN_BLOCKED
};

input group "16 — Phục hồi thích ứng bằng Hedge"
input eRecoveryMode          RecoveryMode_               = recovery_OFF;     // Chế độ Recovery: TẮT / QUAN SÁT / HOẠT ĐỘNG
input long                   RecoveryMagic_              = 20260807;        // Magic riêng cho lệnh Hedge Recovery; phải khác Core Magic
input int                    RecoveryStartAfterDca_      = 5;               // Kích hoạt sau số lệnh DCA; không tính lệnh Core đầu tiên
input double                 HedgeGapPips_               = 50.0;            // Giá đi bất lợi thêm bao nhiêu pip sau điểm kích hoạt thì mở Hedge
input double                 HedgeTPPips_                = 50.0;            // TP ảo của Hedge tính từ hòa vốn ròng; không đặt broker TP
input double                 HedgePartialClosePercent_   = 50.0;            // Phần trăm khối lượng Hedge sẽ chốt khi TP ảo đạt
input eRecoveryCoreCloseMode CoreCloseMode_              = recovery_Oldest; // Cách dùng lợi nhuận Hedge đã chốt để giảm Core đang lỗ
input double                 HedgeLockNetProfitPips_     = 3.0;             // Mức lợi nhuận tối thiểu muốn khóa bằng SL cho Hedge còn lại (pip)
input double                 HedgeLockSafetyBufferPips_  = 1.0;             // Biên an toàn vượt hòa vốn ròng khi đặt SL khóa Hedge (pip)
input double                 ReHedgeGapPips_             = 50.0;            // Khoảng bất lợi từ điểm chốt Hedge để mở thế hệ Hedge kế tiếp (pip)
input bool                   RecoveryOneOrderPerBar_     = false;           // RH: tối đa 1 lệnh mở mỗi nến chart/hướng, kể cả mở lại sau BE/SL
input int                    MaxHedgeGenerations_        = 5;               // Số thế hệ Hedge tối đa; hợp lệ từ 1 đến Max

// T15: keep all Recovery-owned semantic inputs visible before the persistence
// layer is parsed. This lets the durable state bind itself to the complete
// Recovery policy instead of only RecoveryStartAfterDca_.
input group "17 — DCA khi Recovery đang hoạt động"
input bool   ContinueDcaAfterHedge_       = false; // Tiếp tục DCA Core sau khi Hedge đã hoạt động; false = khóa DCA
input double MinHedgeCoveragePercent_     = 0.0;   // Coverage Hedge tối thiểu để cho phép DCA (%); 0 = tắt điều kiện
input double TargetRecoveryCorridorPips_  = 0.0;   // Hành lang lợi nhuận mục tiêu (pip); đạt mục tiêu thì dừng thêm DCA; 0 = tắt
input bool   RecoveryTesterResumeState_   = false; // Strategy Tester: true chỉ khi cố ý test restart/resume; false = mỗi pass bắt đầu sạch

struct SRecoveryFoundationConfig
{
   eRecoveryMode          mode;
   long                   recoveryMagic;
   int                    startAfterDca;
   double                 hedgeGapPips;
   double                 hedgeTpPips;
   double                 hedgePartialClosePercent;
   eRecoveryCoreCloseMode coreCloseMode;
   double                 hedgeLockNetProfitPips;
   double                 hedgeLockSafetyBufferPips;
   double                 reHedgeGapPips;
   int                    maxHedgeGenerations;
};

void Recovery_LoadFoundationConfig(SRecoveryFoundationConfig &cfg)
{
   cfg.mode                      = RecoveryMode_;
   cfg.recoveryMagic             = RecoveryMagic_;
   cfg.startAfterDca             = RecoveryStartAfterDca_;
   cfg.hedgeGapPips              = HedgeGapPips_;
   cfg.hedgeTpPips               = HedgeTPPips_;
   cfg.hedgePartialClosePercent  = HedgePartialClosePercent_;
   cfg.coreCloseMode             = CoreCloseMode_;
   cfg.hedgeLockNetProfitPips    = HedgeLockNetProfitPips_;
   cfg.hedgeLockSafetyBufferPips = HedgeLockSafetyBufferPips_;
   cfg.reHedgeGapPips            = ReHedgeGapPips_;
   cfg.maxHedgeGenerations       = MaxHedgeGenerations_;
}

// RETRO-A7: tester persistence is isolated by default. Live/forward runtime
// always reuses durable state; tester reuse requires explicit operator intent.
bool Recovery_ShouldReusePersistedStatePure(const bool isTester,
                                             const bool testerResumeState)
{
   return !isTester || testerResumeState;
}

// Deterministic FNV-1a over the UTF-16 code units used by MQL strings.
uint Recovery_Fnv1aTextPure(const string text)
{
   uint h = 2166136261;
   for(int i = 0; i < StringLen(text); i++)
   {
      ushort ch = (ushort)StringGetCharacter(text, i);
      h ^= (uint)(ch & 0x00ff); h *= 16777619;
      h ^= (uint)((ch >> 8) & 0x00ff); h *= 16777619;
   }
   return h;
}

uint Recovery_SemanticConfigFingerprintPure(const eRecoveryMode mode,
                                             const long recoveryMagic,
                                             const int startAfterDca,
                                             const double hedgeGapPips,
                                             const double hedgeTpPips,
                                             const double hedgePartialClosePercent,
                                             const eRecoveryCoreCloseMode coreCloseMode,
                                             const double hedgeLockNetProfitPips,
                                             const double hedgeLockSafetyBufferPips,
                                             const double reHedgeGapPips,
                                             const int maxHedgeGenerations,
                                             const bool continueDcaAfterHedge,
                                             const double minHedgeCoveragePercent,
                                             const double targetRecoveryCorridorPips)
{
   string canonical =
      "mode=" + (string)(int)mode +
      "|recoveryMagic=" + (string)recoveryMagic +
      "|startAfterDca=" + (string)startAfterDca +
      "|hedgeGap=" + DoubleToString(hedgeGapPips, 12) +
      "|hedgeTp=" + DoubleToString(hedgeTpPips, 12) +
      "|partial=" + DoubleToString(hedgePartialClosePercent, 12) +
      "|coreClose=" + (string)(int)coreCloseMode +
      "|lockProfit=" + DoubleToString(hedgeLockNetProfitPips, 12) +
      "|lockBuffer=" + DoubleToString(hedgeLockSafetyBufferPips, 12) +
      "|rehedgeGap=" + DoubleToString(reHedgeGapPips, 12) +
      "|maxGen=" + (string)maxHedgeGenerations +
      "|continueDca=" + (continueDcaAfterHedge ? "1" : "0") +
      "|minCoverage=" + DoubleToString(minHedgeCoveragePercent, 12) +
      "|targetCorridor=" + DoubleToString(targetRecoveryCorridorPips, 12);
   return Recovery_Fnv1aTextPure(canonical);
}

uint Recovery_CurrentSemanticConfigFingerprint()
{
   return Recovery_SemanticConfigFingerprintPure(RecoveryMode_,
                                                  RecoveryMagic_,
                                                  RecoveryStartAfterDca_,
                                                  HedgeGapPips_,
                                                  HedgeTPPips_,
                                                  HedgePartialClosePercent_,
                                                  CoreCloseMode_,
                                                  HedgeLockNetProfitPips_,
                                                  HedgeLockSafetyBufferPips_,
                                                  ReHedgeGapPips_,
                                                  MaxHedgeGenerations_,
                                                  ContinueDcaAfterHedge_,
                                                  MinHedgeCoveragePercent_,
                                                  TargetRecoveryCorridorPips_);
}

bool Recovery_ModeValid(const eRecoveryMode mode)
{
   return mode == recovery_OFF || mode == recovery_SHADOW || mode == recovery_ACTIVE;
}

bool Recovery_CoreCloseModeValid(const eRecoveryCoreCloseMode mode)
{
   return mode == recovery_Oldest || mode == recovery_Newest ||
          mode == recovery_Lossiest || mode == recovery_ProRata;
}

int Recovery_CycleKey(const eRecoveryCoreDirection dir)
{
   return dir == recovery_CORE_BUY ? 1 : 2;
}

string Recovery_DirectionName(const eRecoveryCoreDirection dir)
{
   return dir == recovery_CORE_BUY ? "BUY_CORE" : "SELL_CORE";
}

string Recovery_StateName(const eRecoveryState state)
{
   switch(state)
   {
      case recovery_CORE_ONLY:          return "CORE_ONLY";
      case recovery_ARMED:              return "ARMED";
      case recovery_HEDGE_BUILDING:     return "HEDGE_BUILDING";
      case recovery_HEDGE_ACTIVE:       return "HEDGE_ACTIVE";
      case recovery_HEDGE_TP_PENDING:   return "HEDGE_TP_PENDING";
      case recovery_CORE_CLOSE_PENDING: return "CORE_CLOSE_PENDING";
      case recovery_HEDGE_LOCK_PENDING: return "HEDGE_LOCK_PENDING";
      case recovery_HEDGE_LOCKED:       return "HEDGE_LOCKED";
      case recovery_REHEDGE_PENDING:    return "REHEDGE_PENDING";
      case recovery_PAUSE_SOFT:         return "PAUSE_SOFT";
      case recovery_PAUSE_HARD:         return "PAUSE_HARD";
      case recovery_RECONCILE_REQUIRED: return "RECONCILE_REQUIRED";
      case recovery_GLOBAL_STOP:        return "GLOBAL_STOP";
      case recovery_COMPLETED:          return "COMPLETED";
   }
   return "UNKNOWN";
}

bool Recovery_ValidateFoundation(const eRecoveryMode mode,
                                 const long coreMagic,
                                 const long recoveryMagic,
                                 const int startAfterDca,
                                 const long marginMode,
                                 string &why)
{
   why = "";
   if(!Recovery_ModeValid(mode))
   {
      why = "RecoveryMode_ invalid";
      return false;
   }

   if(mode == recovery_OFF) return true;

   if(coreMagic <= 0)
   {
      why = "Core Magic must be > 0 when Recovery is enabled";
      return false;
   }
   if(recoveryMagic <= 0)
   {
      why = "RecoveryMagic_ must be > 0 when Recovery is enabled";
      return false;
   }
   if(recoveryMagic == coreMagic)
   {
      why = "RecoveryMagic_ must differ from Core Magic";
      return false;
   }
   if(startAfterDca < 0)
   {
      why = "RecoveryStartAfterDca_ must be >= 0";
      return false;
   }
   if(mode == recovery_ACTIVE && marginMode != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
   {
      why = "Recovery ACTIVE requires ACCOUNT_MARGIN_MODE_RETAIL_HEDGING";
      return false;
   }
   return true;
}

bool Recovery_ValidateShadowConfig(const eRecoveryMode mode,
                                   const double hedgeGapPips,
                                   string &why)
{
   why = "";
   if(mode == recovery_OFF) return true;
   if(hedgeGapPips < 0.0)
   {
      why = "HedgeGapPips_ must be >= 0";
      return false;
   }
   return true;
}

bool Recovery_ValidateT5Config(const eRecoveryMode mode,
                               const double hedgeTpPips,
                               const double partialClosePercent,
                               const eRecoveryCoreCloseMode coreCloseMode,
                               string &why)
{
   why = "";
   if(mode == recovery_OFF) return true;
   if(hedgeTpPips < 0.0)
   {
      why = "HedgeTPPips_ must be >= 0";
      return false;
   }
   if(partialClosePercent <= 0.0 || partialClosePercent > 100.0)
   {
      why = "HedgePartialClosePercent_ must be in (0,100]";
      return false;
   }
   if(!Recovery_CoreCloseModeValid(coreCloseMode))
   {
      why = "CoreCloseMode_ invalid";
      return false;
   }
   return true;
}

bool Recovery_ValidateT6Config(const eRecoveryMode mode,
                               const double lockNetProfitPips,
                               const double lockSafetyBufferPips,
                               const double reHedgeGapPips,
                               const int maxHedgeGenerations,
                               string &why)
{
   why = "";
   if(mode == recovery_OFF) return true;
   if(lockNetProfitPips < 0.0)
   {
      why = "HedgeLockNetProfitPips_ must be >= 0";
      return false;
   }
   if(lockSafetyBufferPips <= 0.0)
   {
      why = "HedgeLockSafetyBufferPips_ must be > 0 for strict net-positive protection";
      return false;
   }
   if(reHedgeGapPips < 0.0)
   {
      why = "ReHedgeGapPips_ must be >= 0";
      return false;
   }
   if(maxHedgeGenerations < 1)
   {
      why = "MaxHedgeGenerations_ must be >= 1";
      return false;
   }
   return true;
}

#endif // BD_RECOVERY_TYPES_MQH