//+------------------------------------------------------------------+
//| RunT177MigrationTests.mq5 — T17.7 C5 migration/fingerprint locks|
//+------------------------------------------------------------------+
#property script_show_inputs
#include <BlackDragon/Recovery/RecoveryT177MigrationPolicy.mqh>
#include <BlackDragon/Recovery/RecoveryArcsPersistence.mqh>

int g_pass=0, g_fail=0;
void Check(const string name,const bool cond)
{
   if(cond){g_pass++;return;}
   g_fail++;
   Print("FAIL: ",name);
}
bool Near(const double a,const double b,const double eps=1e-9)
{ return MathAbs(a-b)<=eps; }

void OnStart()
{
   Check("legacy both false -> OFF",
         Recovery_T177OverlapPolicyPure(OVERLAP_LEGACY_AUTO,false,false)==OVERLAP_OFF);
   Check("legacy overlap -> CORE_ONLY",
         Recovery_T177OverlapPolicyPure(OVERLAP_LEGACY_AUTO,true,false)==OVERLAP_CORE_ONLY);
   Check("legacy after hedge wins",
         Recovery_T177OverlapPolicyPure(OVERLAP_LEGACY_AUTO,true,true)==OVERLAP_ALLOW_DURING_RECOVERY);
   Check("legacy contradictory after hedge wins",
         Recovery_T177OverlapPolicyPure(OVERLAP_LEGACY_AUTO,false,true)==OVERLAP_ALLOW_DURING_RECOVERY);
   Check("explicit OFF overrides legacy",
         Recovery_T177OverlapPolicyPure(OVERLAP_OFF,true,true)==OVERLAP_OFF);
   Check("explicit ALLOW overrides legacy",
         Recovery_T177OverlapPolicyPure(OVERLAP_ALLOW_DURING_RECOVERY,false,false)==OVERLAP_ALLOW_DURING_RECOVERY);
   Check("explicit CORE decision enabled with old bool off",
         Recovery_T177OverlapDecisionEnabledPure(OVERLAP_CORE_ONLY,false,false));
   Check("explicit OFF decision disabled",
         !Recovery_T177OverlapDecisionEnabledPure(OVERLAP_OFF,true,true));

   Check("target AUTO uses legacy", Near(Recovery_T177TargetCoveragePure(0.0,160.0),160.0));
   Check("target explicit wins", Near(Recovery_T177TargetCoveragePure(85.0,160.0),85.0));
   Check("cap AUTO uses legacy", Near(Recovery_T177AbsoluteCapPure(-1.0,90.0),90.0));
   Check("cap zero disables extra hard cap", Near(Recovery_T177AbsoluteCapPure(0.0,90.0),0.0));
   Check("final hard cap", Near(Recovery_T177EffectiveFinalCoveragePure(100.0,85.0,160.0,90.0),85.0));
   Check("final no extra cap", Near(Recovery_T177EffectiveFinalCoveragePure(100.0,0.0,160.0,90.0),100.0));

   Check("legacy global bool OFF migrates to N=0",
         Recovery_T177EffectiveGlobalSlAfterPure(false,5)==0);
   Check("N=0 means Global SL OFF",
         Recovery_T177EffectiveGlobalSlAfterPure(true,0)==0);
   Check("legacy enabled N preserved",
         Recovery_T177EffectiveGlobalSlAfterPure(true,5)==5);

   Check("legacy selectors are migration-compatible",
         Recovery_T177MigrationSelectorsLegacyPure(OVERLAP_LEGACY_AUTO,0.0,-1.0,true,5));
   Check("explicit target rotates semantic",
         !Recovery_T177MigrationSelectorsLegacyPure(OVERLAP_LEGACY_AUTO,85.0,-1.0,true,5));
   Check("new N=0 meaning does not accept old valid identity",
         !Recovery_T177MigrationSelectorsLegacyPure(OVERLAP_LEGACY_AUTO,0.0,-1.0,true,0));

   string dcaOffA=Recovery_T177ConditionalDcaTextPure(false,80.0,20.0);
   string dcaOffB=Recovery_T177ConditionalDcaTextPure(false,120.0,99.0);
   string dcaOnA=Recovery_T177ConditionalDcaTextPure(true,80.0,20.0);
   string dcaOnB=Recovery_T177ConditionalDcaTextPure(true,120.0,99.0);
   Check("inactive DCA knobs excluded from fingerprint text",dcaOffA==dcaOffB);
   Check("active DCA knobs affect fingerprint text",dcaOnA!=dcaOnB);

   string globalOffA=Recovery_T177ConditionalGlobalTextPure(0,3.0,10.0);
   string globalOffB=Recovery_T177ConditionalGlobalTextPure(0,99.0,77.0);
   string globalOnA=Recovery_T177ConditionalGlobalTextPure(5,3.0,10.0);
   string globalOnB=Recovery_T177ConditionalGlobalTextPure(5,99.0,77.0);
   Check("inactive Global SL knobs excluded",globalOffA==globalOffB);
   Check("active Global SL knobs included",globalOnA!=globalOnB);

   string overlapOffA=Recovery_T177ConditionalOverlapTextPure(OVERLAP_OFF,8,3.0,false);
   string overlapOffB=Recovery_T177ConditionalOverlapTextPure(OVERLAP_OFF,20,50.0,true);
   string overlapOnA=Recovery_T177ConditionalOverlapTextPure(OVERLAP_CORE_ONLY,8,3.0,false);
   string overlapOnB=Recovery_T177ConditionalOverlapTextPure(OVERLAP_CORE_ONLY,20,50.0,true);
   Check("inactive Overlap knobs excluded",overlapOffA==overlapOffB);
   Check("active Overlap knobs included",overlapOnA!=overlapOnB);

   Check("CORE_ONLY blocks live Recovery hedge",
         Recovery_T177OverlapCoreOnlyBlockedPure(recovery_CORE_ONLY,0.01));
   Check("CORE_ONLY allows ARMED with no hedge",
         !Recovery_T177OverlapCoreOnlyBlockedPure(recovery_ARMED,0.0));
   Check("CORE_ONLY blocks active Recovery state",
         Recovery_T177OverlapCoreOnlyBlockedPure(recovery_HEDGE_ACTIVE,0.0));

   Check("legacy persistence IDLE boundary safe",
         Recovery_T177LegacyPersistPhaseSafePure(ARCS_IDLE));
   Check("legacy persistence ARMED boundary safe",
         Recovery_T177LegacyPersistPhaseSafePure(ARCS_ARMED));
   Check("legacy persistence REVERSAL_HOLD boundary safe",
         Recovery_T177LegacyPersistPhaseSafePure(ARCS_REVERSAL_HOLD));
   Check("legacy persistence BUILDING fails closed",
         !Recovery_T177LegacyPersistPhaseSafePure(ARCS_BUILDING));
   Check("legacy persistence ACTIVE fails closed",
         !Recovery_T177LegacyPersistPhaseSafePure(ARCS_ACTIVE));
   Check("legacy EMPTY layer safe",
         Recovery_T177LegacyPersistLayerSafePure(ARCS_LAYER_EMPTY));
   Check("legacy CLOSED layer safe",
         Recovery_T177LegacyPersistLayerSafePure(ARCS_LAYER_CLOSED));
   Check("legacy BUILDING layer fails closed",
         !Recovery_T177LegacyPersistLayerSafePure(ARCS_LAYER_BUILDING));
   Check("legacy ACTIVE layer fails closed",
         !Recovery_T177LegacyPersistLayerSafePure(ARCS_LAYER_ACTIVE));

   Check("C5 fingerprint revision rotates default semantic",
         Recovery_T177SemanticFingerprintC5()!=Recovery_T177LegacySemanticFingerprintC5());

   Print("T17.7 C5 migration tests: ",g_pass," passed, ",g_fail," failed");
   if(g_fail==0) Print("ALL GREEN");
   else Print("TESTS FAILED");
}
