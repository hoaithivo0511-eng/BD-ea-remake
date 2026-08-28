#property strict
#include <BlackDragon/Recovery/RecoveryMutationPolicy.mqh>
#include <BlackDragon/Recovery/RecoveryT16Config.mqh>

int g_pass=0,g_fail=0;
void T(const bool ok,const string name)
{
   if(ok) g_pass++;
   else { g_fail++; Print("FAIL: ",name); }
}

void OnStart()
{
   T(Recovery_OverlapCapabilityPolicyPure(recovery_HEDGE_BUILDING,
                                          true,false,false,false)==recovery_OVERLAP_COORDINATE,
     "quiet HEDGE_BUILDING coordinates Overlap");
   T(Recovery_OverlapCapabilityPolicyPure(recovery_HEDGE_BUILDING,
                                          true,true,false,false)==recovery_OVERLAP_DEFER,
     "durable Recovery mutation blocks Overlap");
   T(Recovery_OverlapCapabilityPolicyPure(recovery_HEDGE_BUILDING,
                                          true,false,true,false)==recovery_OVERLAP_DEFER,
     "execution journal mutation blocks Overlap");
   T(Recovery_OverlapCapabilityPolicyPure(recovery_HEDGE_BUILDING,
                                          true,false,false,true)==recovery_OVERLAP_DEFER,
     "coordinator obligation blocks Overlap");
   T(Recovery_OverlapCapabilityPolicyPure(recovery_HEDGE_BUILDING,
                                          false,false,false,false)==recovery_OVERLAP_DEFER,
     "unready Recovery blocks Overlap");
   T(Recovery_OverlapCapabilityPolicyPure(recovery_HEDGE_TP_PENDING,
                                          true,false,false,false)==recovery_OVERLAP_DEFER,
     "mutation state remains blocked while quiet");

   long coreAfter=80;
   long retainedPrior=50;
   long liveGeneration=18;
   long retainedHedge=retainedPrior+liveGeneration;
   T(Recovery_OverlapRetainedWithinHardCapPure(coreAfter,retainedHedge,90.0),
     "68 retained Hedge is within Core80 x90 percent cap72");
   T(!Recovery_OverlapRetainedWithinHardCapPure(70,retainedHedge,90.0),
     "68 retained Hedge exceeds Core70 x90 percent cap63");

   long computed=Recovery_T177FinalGenerationRawUnitsPure(coreAfter,
                                                          retainedPrior,
                                                          90.0);
   long target=Recovery_T176RebasedGenerationTargetPure(liveGeneration,computed);
   T(computed==22 && target==22,
     "post-trim Core denominator refresh rebases generation target to22");
   T(target-liveGeneration==4,
     "coordinated Overlap refresh leaves four units for ladder continuation");

   Print("T17.15 native Overlap capability: ",g_pass,
         " passed, ",g_fail," failed");
   if(g_fail==0) Print("ALL GREEN");
   if(g_fail>0) ExpertRemove();
}
