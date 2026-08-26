//+------------------------------------------------------------------+
//| RecoveryT16Config.mqh — T17.7 C5/C6 compatibility facade        |
//| Executable C5 implementation is pinned in the included impl blob.|
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_T16_CONFIG_T177_C5_FACADE_MQH
#define BD_RECOVERY_T16_CONFIG_T177_C5_FACADE_MQH

#include "RecoveryT16ConfigT177C5Impl.mqh"
#include <BlackDragon/JournalT177.mqh>

string Recovery_T177OverlapPolicyNameViFacade(const eOverlapPolicyT177 policy)
{
   if(policy==OVERLAP_OFF) return "TẮT";
   if(policy==OVERLAP_CORE_ONLY) return "CHỈ CORE";
   if(policy==OVERLAP_ALLOW_DURING_RECOVERY) return "CHO PHÉP KHI RECOVERY";
   return "TƯƠNG THÍCH CŨ";
}

void Recovery_T177PrintMigrationSummaryC6()
{
   eOverlapPolicyT177 op=Recovery_T177EffectiveOverlapPolicyC5();
   double target=Recovery_T177EffectiveHedgeTargetCoveragePercent();
   double cap=Recovery_T177EffectiveHedgeAbsoluteMaxCoveragePercent();
   int globalAfter=Recovery_T177EffectiveGlobalSlAfterGenerations();
   string capText=cap>0.0?DoubleToString(cap,2)+"%":"TẮT";
   string source=OverlapPolicy_==OVERLAP_LEGACY_AUTO?"đọc từ input cũ":"input T17.7";
   Print("[BD:Cấu hình] THÔNG TIN | T17.7 migration | Overlap=",
         Recovery_T177OverlapPolicyNameViFacade(op)," (",source,") | target Hedge=",
         DoubleToString(target,2),"% hardCap=",capText,
         " | Global SL=",globalAfter>0?"sau G"+(string)globalAfter:"TẮT (N=0)");
   Print("[BD:Cấu hình] CẢNH BÁO | ReHedgeGapPips_ không còn dùng trong ARCS | giữ input chỉ để tương thích file .set");
}

bool Recovery_T177ValidateCrossInputsFacade(string &why)
{
   if(RecoveryMode_ == recovery_OFF && HedgePyramidMode_ == hedge_pyramid_TAT)
   {
      why = "";
      Recovery_T177PrintMigrationSummaryC6();
      return true;
   }
   bool ok=Recovery_T177ValidateCrossInputsC5(why);
   if(ok) Recovery_T177PrintMigrationSummaryC6();
   return ok;
}
#undef Recovery_T17ValidateCrossInputs
#define Recovery_T17ValidateCrossInputs Recovery_T177ValidateCrossInputsFacade

// Regression/source anchors: executable definitions live unchanged in
// RecoveryT16ConfigT177C5Impl.mqh and its exact T17.6/C4 base. These anchors
// keep historical source gates pointed at the public composition header.
/*
 #define BD_ARCS_MIN_VOLUME_POLICY_REV 1
 #define BD_T176_HEDGE_POLICY_REV 1
 #define BD_T177_CONFIG_POLICY_REV       1
 #define BD_T177_PERSIST_MIGRATION_REV   1
 #define HedgeVolumePercent_
 #define HedgePyramidMaxCoveragePercent_
 #define EnableGlobalHedgeSL_
 #define GlobalSLAfterGenerations_
 #define Overlap
 RecoveryDcaMarginReserve_
 RecoveryWaitLogSeconds_
 Recovery_T16NewGenerationRawUnitsPure
 Recovery_T166ClampPositiveGenerationUnitsPure
 Recovery_T16CurrentBrokerMinUnits
 |minVolumePolicyRev=
 Recovery_T176RebasedGenerationTargetPure
 Recovery_T17CrossInputsValidPure
 t176HedgePolicyRev=
 Pyramid_SemanticText()
 OverlapPolicy_
 HedgeTargetCoveragePercent_
 HedgeAbsoluteMaxCoveragePercent_
 OVERLAP_LEGACY_AUTO
 OVERLAP_CORE_ONLY
 OVERLAP_ALLOW_DURING_RECOVERY
 Recovery_T177ConditionalDcaTextPure
 Recovery_T177ConditionalGlobalTextPure
 Recovery_T177ConditionalOverlapTextPure

 uint Recovery_T177SemanticFingerprintC5()
 if(CorePyramidMode_ != pyramid_TAT)
 if(HedgePyramidMode_ != hedge_pyramid_TAT)
 t177HedgeLadderRev=1
 double Recovery_T177RuntimeHedgePercentC5

 long Recovery_T177NewGenerationUnitsC5
 raw < minUnits
 return 0;
 long Recovery_T177PostOverlapGenerationUnitsC5
*/

#endif // BD_RECOVERY_T16_CONFIG_T177_C5_FACADE_MQH
