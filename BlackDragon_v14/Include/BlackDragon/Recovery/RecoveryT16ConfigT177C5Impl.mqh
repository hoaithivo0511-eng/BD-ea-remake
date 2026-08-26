//+------------------------------------------------------------------+
//| RecoveryT16Config.mqh — T17.7 C5 compatibility/migration layer  |
//| Keeps T17.6/C4 source intact, overrides only active semantics.    |
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_T16_CONFIG_T177_C5_WRAPPER_MQH
#define BD_RECOVERY_T16_CONFIG_T177_C5_WRAPPER_MQH

#include "RecoveryT16ConfigT177C4Base.mqh"
#include <BlackDragon/Pyramid/PyramidAnchorT177.mqh>

enum eOverlapPolicyT177
{
   OVERLAP_LEGACY_AUTO = -1,             // Giữ nghĩa file .set cũ
   OVERLAP_OFF = 0,                      // Tắt Overlap
   OVERLAP_CORE_ONLY = 1,                // Chỉ Overlap khi side chưa có Hedge Recovery
   OVERLAP_ALLOW_DURING_RECOVERY = 2     // Cho phép qua coordinator khi Recovery đang hoạt động
};

input group "24B — T17.7: CẤU HÌNH GỘP / TƯƠNG THÍCH"
input eOverlapPolicyT177 OverlapPolicy_ = OVERLAP_LEGACY_AUTO; // AUTO: đọc Overlap + OverlapAfterHedge_ cũ
input double HedgeTargetCoveragePercent_ = 0.0; // Target cuối TOTAL Hedge/Core (%); 0 = dùng HedgeVolumePercent_ cũ
input double HedgeAbsoluteMaxCoveragePercent_ = -1.0; // Hard cap (%); -1 = dùng cap cũ, 0 = không thêm hard cap

#define BD_T177_CONFIG_POLICY_REV       1
#define BD_T177_PERSIST_MIGRATION_REV   1

bool Recovery_T177OverlapPolicyValidPure(const int policy)
{
   return policy == (int)OVERLAP_LEGACY_AUTO ||
          policy == (int)OVERLAP_OFF ||
          policy == (int)OVERLAP_CORE_ONLY ||
          policy == (int)OVERLAP_ALLOW_DURING_RECOVERY;
}

eOverlapPolicyT177 Recovery_T177OverlapPolicyPure(const eOverlapPolicyT177 requested,
                                                   const bool legacyOverlap,
                                                   const bool legacyAfterHedge)
{
   if(requested != OVERLAP_LEGACY_AUTO) return requested;
   if(legacyAfterHedge) return OVERLAP_ALLOW_DURING_RECOVERY;
   return legacyOverlap ? OVERLAP_CORE_ONLY : OVERLAP_OFF;
}

bool Recovery_T177OverlapDecisionEnabledPure(const eOverlapPolicyT177 requested,
                                             const bool legacyOverlap,
                                             const bool legacyAfterHedge)
{
   return Recovery_T177OverlapPolicyPure(requested, legacyOverlap,
                                         legacyAfterHedge) != OVERLAP_OFF;
}

eOverlapPolicyT177 Recovery_T177EffectiveOverlapPolicyC5()
{
   return Recovery_T177OverlapPolicyPure(OverlapPolicy_, Overlap,
                                         OverlapAfterHedge_);
}

bool Recovery_T177OverlapDecisionEnabled()
{
   return Recovery_T177OverlapDecisionEnabledPure(OverlapPolicy_, Overlap,
                                                   OverlapAfterHedge_);
}

double Recovery_T177TargetCoveragePure(const double requested,
                                        const double legacyTarget)
{
   return requested > 0.0 ? requested : legacyTarget;
}

double Recovery_T177AbsoluteCapPure(const double requestedCap,
                                    const double legacyCap)
{
   return requestedCap >= 0.0 ? requestedCap : legacyCap;
}

double Recovery_T177EffectiveFinalCoveragePure(const double requestedTarget,
                                                const double requestedCap,
                                                const double legacyTarget,
                                                const double legacyCap)
{
   double target = Recovery_T177TargetCoveragePure(requestedTarget, legacyTarget);
   double cap = Recovery_T177AbsoluteCapPure(requestedCap, legacyCap);
   if(target <= 0.0) return 0.0;
   return cap > 0.0 ? MathMin(target, cap) : target;
}

double Recovery_T177EffectiveHedgeTargetCoveragePercent()
{
   return Recovery_T177TargetCoveragePure(HedgeTargetCoveragePercent_,
                                          HedgeVolumePercent_);
}

double Recovery_T177EffectiveHedgeAbsoluteMaxCoveragePercent()
{
   return Recovery_T177AbsoluteCapPure(HedgeAbsoluteMaxCoveragePercent_,
                                       HedgePyramidMaxCoveragePercent_);
}

int Recovery_T177EffectiveGlobalSlAfterPure(const bool legacyEnable,
                                            const int configuredAfter)
{
   if(!legacyEnable || configuredAfter <= 0) return 0;
   return configuredAfter;
}

int Recovery_T177EffectiveGlobalSlAfterGenerations()
{
   return Recovery_T177EffectiveGlobalSlAfterPure(EnableGlobalHedgeSL_,
                                                  GlobalSLAfterGenerations_);
}

bool Recovery_T177EffectiveGlobalSlEnabled()
{
   return Recovery_T177EffectiveGlobalSlAfterGenerations() > 0;
}

bool Recovery_T177MigrationSelectorsLegacyPure(const eOverlapPolicyT177 overlapPolicy,
                                               const double newTarget,
                                               const double newCap,
                                               const bool legacyGlobalEnable,
                                               const int globalAfter)
{
   if(overlapPolicy != OVERLAP_LEGACY_AUTO) return false;
   if(newTarget > 0.0) return false;
   if(newCap >= 0.0) return false;
   // Enable=true + N=0 was invalid in the old contract and now means OFF.
   // Do not accept an old persisted identity for that changed meaning.
   if(legacyGlobalEnable && globalAfter <= 0) return false;
   return true;
}

bool Recovery_T177CanAcceptLegacyPersistenceC5()
{
   return Recovery_T177MigrationSelectorsLegacyPure(OverlapPolicy_,
                                                     HedgeTargetCoveragePercent_,
                                                     HedgeAbsoluteMaxCoveragePercent_,
                                                     EnableGlobalHedgeSL_,
                                                     GlobalSLAfterGenerations_);
}

string Recovery_T177ConditionalDcaTextPure(const bool continueDca,
                                           const double minCoverage,
                                           const double corridor)
{
   string s = "|continueDca=" + (continueDca ? "1" : "0");
   if(continueDca)
      s += "|minCoverage=" + DoubleToString(minCoverage, 12) +
           "|targetCorridor=" + DoubleToString(corridor, 12);
   return s;
}

string Recovery_T177ConditionalGlobalTextPure(const int globalAfter,
                                              const double globalProfit,
                                              const double reentryBuffer)
{
   string s = "|globalAfter=" + (string)globalAfter;
   if(globalAfter > 0)
      s += "|globalProfit=" + DoubleToString(globalProfit, 12) +
           "|reentryBuffer=" + DoubleToString(reentryBuffer, 12);
   return s;
}

string Recovery_T177ConditionalOverlapTextPure(const eOverlapPolicyT177 policy,
                                               const int orderNumber,
                                               const double overlapPercent,
                                               const bool includeManual)
{
   string s = "|overlapPolicy=" + (string)(int)policy;
   if(policy != OVERLAP_OFF)
      s += "|overlapFrom=" + (string)orderNumber +
           "|overlapPct=" + DoubleToString(overlapPercent, 12) +
           "|overlapManual=" + (includeManual ? "1" : "0");
   return s;
}

// Legacy fingerprint is retained only as a one-time migration proof. New saves
// always use the conditional C5 fingerprint below.
uint Recovery_T177LegacySemanticFingerprintC5()
{
   return Recovery_T16SemanticFingerprint();
}

uint Recovery_T177SemanticFingerprintC5()
{
   double target = Recovery_T177EffectiveHedgeTargetCoveragePercent();
   double cap = Recovery_T177EffectiveHedgeAbsoluteMaxCoveragePercent();
   int globalAfter = Recovery_T177EffectiveGlobalSlAfterGenerations();
   eOverlapPolicyT177 overlapPolicy = Recovery_T177EffectiveOverlapPolicyC5();

   string canonical =
      "t177CfgRev=" + (string)BD_T177_CONFIG_POLICY_REV +
      "|persistMigrationRev=" + (string)BD_T177_PERSIST_MIGRATION_REV +
      "|mode=" + (string)(int)RecoveryMode_ +
      "|recoveryMagic=" + (string)RecoveryMagic_ +
      "|startAfterDca=" + (string)RecoveryStartAfterDca_ +
      "|hedgeGap=" + DoubleToString(HedgeGapPips_, 12) +
      "|hedgeTp=" + DoubleToString(HedgeTPPips_, 12) +
      "|partial=" + DoubleToString(HedgePartialClosePercent_, 12) +
      "|coreClose=" + (string)(int)CoreCloseMode_ +
      "|lockProfit=" + DoubleToString(HedgeLockNetProfitPips_, 12) +
      "|lockBuffer=" + DoubleToString(HedgeLockSafetyBufferPips_, 12) +
      "|maxGen=" + (string)MaxHedgeGenerations_ +
      Recovery_T177ConditionalDcaTextPure(ContinueDcaAfterHedge_,
                                          MinHedgeCoveragePercent_,
                                          TargetRecoveryCorridorPips_) +
      "|sizing=" + (string)(int)RecoverySizingPolicy_ +
      "|hedgeTarget=" + DoubleToString(target, 12) +
      "|slMode=" + (string)(int)HedgeSLMode_ +
      Recovery_T177ConditionalGlobalTextPure(globalAfter,
                                             GlobalHedgeSLNetProfitPips_,
                                             RecoveryReentryBufferPips_) +
      Recovery_T177ConditionalOverlapTextPure(overlapPolicy,
                                              OverlapOrderNumber,
                                              OverlapPercent,
                                              flag_Hand_Ord) +
      "|dcaMarginReserve=" + (RecoveryDcaMarginReserve_ ? "1" : "0") +
      "|minVolumePolicyRev=" + (string)BD_ARCS_MIN_VOLUME_POLICY_REV +
      "|layerCapacity=" + (string)BD_ARCS_MAX_LAYERS;

   // ReHedgeGapPips_ is intentionally absent: ARCS no longer executes it.
   if(CorePyramidMode_ != pyramid_TAT)
   {
      canonical +=
         "|pyrRev=" + (string)BD_PYRAMID_POLICY_REV +
         "|coreMode=" + (string)(int)CorePyramidMode_ +
         "|coreAnchorRev=" + (string)BD_T177_ANCHOR_POLICY_REV +
         "|coreAnchorMode=" + (string)(int)CorePyramidAnchorMode_ +
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
         "|coreTrend=" + (PyramidRequireTrend_ ? "1" : "0");
   }

   if(HedgePyramidMode_ != hedge_pyramid_TAT)
   {
      canonical +=
         "|pyrRev=" + (string)BD_PYRAMID_POLICY_REV +
         "|hedgeMode=" + (string)(int)HedgePyramidMode_ +
         "|hedgeTarget=" + DoubleToString(target, 12) +
         "|hedgeCov=" + HedgePyramidCoverageSequence_ +
         "|hedgeGap=" + HedgePyramidGapSequence_ +
         "|hedgeAbsCap=" + DoubleToString(cap, 12) +
         "|hedgeReserve=" + (HedgePyramidReserveFullTarget_ ? "1" : "0") +
         "|hedgeRoomTp=" + DoubleToString(HedgePyramidMinRoomToTPPips_, 12) +
         "|hedgeLockAdd=" + (HedgePyramidLockBeforeAdd_ ? "1" : "0") +
         "|t176HedgePolicyRev=" + (string)BD_T176_HEDGE_POLICY_REV +
         "|t177HedgeLadderRev=1";
   }
   return Recovery_Fnv1aTextPure(canonical);
}

double Recovery_T177RuntimeHedgePercentC5(const double requestedPercent)
{
   if(HedgePyramidMode_ == hedge_pyramid_TAT || requestedPercent <= 0.0)
      return requestedPercent;
   double cap = Recovery_T177EffectiveHedgeAbsoluteMaxCoveragePercent();
   return cap > 0.0 ? MathMin(requestedPercent, cap) : requestedPercent;
}

long Recovery_T177NewGenerationUnitsC5(const eRecoverySizingPolicy policy,
                                       const long coreUnits,
                                       const long existingHedgeUnits,
                                       const double hedgePercent)
{
   double runtimePercent = Recovery_T177RuntimeHedgePercentC5(hedgePercent);
   eRecoverySizingPolicy effectivePolicy =
      HedgePyramidMode_ == hedge_pyramid_TAT ? policy : HEDGE_CAN_BANG;
   long raw = Recovery_T16NewGenerationRawUnitsPure(effectivePolicy,
                                                    coreUnits,
                                                    existingHedgeUnits,
                                                    runtimePercent);
   if(raw <= 0) return 0;
   long minUnits = Recovery_T16CurrentBrokerMinUnits();
   // Staged Hedge may not exceed its executable final target merely to satisfy
   // broker minimum. Stay ARMED/WAIT until Core makes at least minUnits legal.
   if(HedgePyramidMode_ != hedge_pyramid_TAT && minUnits > 0 && raw < minUnits)
      return 0;
   return Recovery_T166ClampPositiveGenerationUnitsPure(raw, minUnits);
}

long Recovery_T177PostOverlapGenerationUnitsC5(const eRecoverySizingPolicy policy,
                                               const long refreshedCoreUnits,
                                               const long refreshedHedgeUnits,
                                               const double hedgePercent)
{
   return Recovery_T177NewGenerationUnitsC5(policy, refreshedCoreUnits,
                                            refreshedHedgeUnits, hedgePercent);
}

bool Recovery_T177CrossInputsValidC5(const eRecoveryMode recoveryMode,
                                     const eHedgePyramidMode hedgePyramidMode,
                                     const bool continueDcaAfterHedge,
                                     const double minHedgeCoveragePercent,
                                     const double finalTarget,
                                     const double absoluteCap)
{
   if(hedgePyramidMode != hedge_pyramid_TAT && recoveryMode == recovery_OFF)
      return false;
   if(finalTarget <= 0.0) return false;
   if(absoluteCap < 0.0) return false;
   if(recoveryMode == recovery_ACTIVE && continueDcaAfterHedge &&
      minHedgeCoveragePercent > 0.0 && hedgePyramidMode != hedge_pyramid_TAT)
   {
      double attainable = absoluteCap > 0.0 ? MathMin(finalTarget, absoluteCap)
                                            : finalTarget;
      if(minHedgeCoveragePercent > attainable + 1e-9) return false;
   }
   return true;
}

bool Recovery_T177ValidateCrossInputsC5(string &why)
{
   why = "";
   if(!Recovery_T177OverlapPolicyValidPure((int)OverlapPolicy_))
   { why = "Chế độ Overlap T17.7 không hợp lệ"; return false; }
   if(HedgeTargetCoveragePercent_ < 0.0)
   { why = "HedgeTargetCoveragePercent_ phải >= 0; 0 = dùng giá trị cũ"; return false; }
   if(HedgeAbsoluteMaxCoveragePercent_ < -1.0 ||
      (HedgeAbsoluteMaxCoveragePercent_ > -1.0 && HedgeAbsoluteMaxCoveragePercent_ < 0.0))
   { why = "HedgeAbsoluteMaxCoveragePercent_ chỉ nhận -1, 0 hoặc số dương"; return false; }

   double target = Recovery_T177EffectiveHedgeTargetCoveragePercent();
   double cap = Recovery_T177EffectiveHedgeAbsoluteMaxCoveragePercent();
   if(!Recovery_T177CrossInputsValidC5(RecoveryMode_, HedgePyramidMode_,
                                       ContinueDcaAfterHedge_,
                                       MinHedgeCoveragePercent_,
                                       target, cap))
   {
      if(HedgePyramidMode_ != hedge_pyramid_TAT && RecoveryMode_ == recovery_OFF)
         why = "Bật Hedge Pyramid yêu cầu RecoveryMode_ khác OFF";
      else if(target <= 0.0)
         why = "Target cuối Hedge phải > 0%";
      else if(cap < 0.0)
         why = "Hard cap Hedge sau migration không hợp lệ";
      else
      {
         double attainable = cap > 0.0 ? MathMin(target, cap) : target;
         why = "MinHedgeCoveragePercent_ vượt target Hedge tối đa=" +
               DoubleToString(attainable, 2) + "%";
      }
      return false;
   }
   return true;
}

bool Recovery_T177ValidateConfigC5(string &why)
{
   why = "";
   if(RecoveryMode_ == recovery_OFF) return true;
   if(!Recovery_T16SizingPolicyValid(RecoverySizingPolicy_))
   { why = "Kiểu xử lý Hedge không hợp lệ"; return false; }
   if(Recovery_T177EffectiveHedgeTargetCoveragePercent() <= 0.0)
   { why = "Target cuối Hedge (%) phải > 0"; return false; }
   if(!Recovery_T16SlModeValid(HedgeSLMode_))
   { why = "Chế độ SL Hedge không hợp lệ"; return false; }
   if(MaxHedgeGenerations_ > BD_ARCS_MAX_LAYERS)
   { why = "Số vòng Hedge tối đa vượt capacity ARCS=" + (string)BD_ARCS_MAX_LAYERS; return false; }
   if(RecoveryWaitLogSeconds_ < 0 || RecoveryWaitLogSeconds_ > 86400)
   { why = "Chu kỳ heartbeat log Recovery phải trong [0,86400] giây"; return false; }
   if(!Recovery_T177ValidateCrossInputsC5(why)) return false;
   if(!Recovery_T164ValidateReachability(RecoveryMode_, Flag_Trade_Buy_, Flag_Trade_Sell_,
                                         MaxOrdersBuy, MaxOrdersSell,
                                         RecoveryStartAfterDca_, why))
      return false;

   int globalAfter = Recovery_T177EffectiveGlobalSlAfterGenerations();
   if(globalAfter > 0)
   {
      if(globalAfter > MaxHedgeGenerations_)
      { why = "Số vòng kích hoạt Global SL không được lớn hơn Số vòng Hedge tối đa"; return false; }
      if(GlobalHedgeSLNetProfitPips_ < 0.0)
      { why = "Lợi nhuận tối thiểu Global SL phải >= 0 pip"; return false; }
      if(RecoveryReentryBufferPips_ < 0.0)
      { why = "Buffer tái kích hoạt Recovery phải >= 0 pip"; return false; }
   }
   return true;
}

bool Recovery_T177UseStackEngineC5()
{
   if(RecoveryMode_ == recovery_ACTIVE &&
      !Recovery_T164ValidateReachabilityPure(RecoveryMode_,
                                             Flag_Trade_Buy_, Flag_Trade_Sell_,
                                             MaxOrdersBuy, MaxOrdersSell,
                                             RecoveryStartAfterDca_))
      return true;
   if(HedgePyramidMode_ != hedge_pyramid_TAT) return true;
   if(RecoverySizingPolicy_ == ARCS_XEP_LOP) return true;
   if(MathAbs(Recovery_T177EffectiveHedgeTargetCoveragePercent() - 100.0) > 1e-12) return true;
   if(HedgeSLMode_ == SL_VIRTUAL) return true;
   if(Recovery_T177EffectiveGlobalSlEnabled()) return true;
   if(Recovery_T177EffectiveOverlapPolicyC5() == OVERLAP_ALLOW_DURING_RECOVERY) return true;
   return false;
}

// C5 runtime aliases. Declarations/functions above were parsed before these
// macros, so they still read the legacy input values for migration purposes.
#define Recovery_T17RuntimeHedgePercent          Recovery_T177RuntimeHedgePercentC5
#define Recovery_T16NewGenerationUnitsPure       Recovery_T177NewGenerationUnitsC5
#define Recovery_T162PostOverlapGenerationUnitsPure Recovery_T177PostOverlapGenerationUnitsC5
#define Recovery_T17ValidateCrossInputs          Recovery_T177ValidateCrossInputsC5
#define Recovery_T16SemanticFingerprint          Recovery_T177SemanticFingerprintC5
#define Recovery_T16ValidateConfig               Recovery_T177ValidateConfigC5
#define Recovery_T16UseStackEngine               Recovery_T177UseStackEngineC5

#define HedgeVolumePercent_               Recovery_T177EffectiveHedgeTargetCoveragePercent()
#define HedgePyramidMaxCoveragePercent_   Recovery_T177EffectiveHedgeAbsoluteMaxCoveragePercent()
#define EnableGlobalHedgeSL_              Recovery_T177EffectiveGlobalSlEnabled()
#define GlobalSLAfterGenerations_         Recovery_T177EffectiveGlobalSlAfterGenerations()
#define Overlap                           Recovery_T177OverlapDecisionEnabled()

#endif // BD_RECOVERY_T16_CONFIG_T177_C5_WRAPPER_MQH
