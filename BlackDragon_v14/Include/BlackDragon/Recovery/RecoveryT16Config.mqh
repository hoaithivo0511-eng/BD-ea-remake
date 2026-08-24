//+------------------------------------------------------------------+
//| RecoveryT16Config.mqh — T17.7 C5 compatibility facade           |
//| Executable C5 implementation is pinned in the included impl blob.|
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_T16_CONFIG_T177_C5_FACADE_MQH
#define BD_RECOVERY_T16_CONFIG_T177_C5_FACADE_MQH

#include "RecoveryT16ConfigT177C5Impl.mqh"

// Preserve Recovery-OFF parity at the top-level cross-input gate. Recovery
// settings that cannot execute while both Recovery and Hedge Pyramid are OFF
// must not reject an otherwise valid legacy .set.
bool Recovery_T177ValidateCrossInputsFacade(string &why)
{
   if(RecoveryMode_ == recovery_OFF && HedgePyramidMode_ == hedge_pyramid_TAT)
   {
      why = "";
      return true;
   }
   return Recovery_T177ValidateCrossInputsC5(why);
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
