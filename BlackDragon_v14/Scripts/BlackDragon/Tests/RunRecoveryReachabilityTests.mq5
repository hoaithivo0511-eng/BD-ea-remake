//+------------------------------------------------------------------+
//| RunRecoveryReachabilityTests.mq5 — T16.4 native pure tests       |
//+------------------------------------------------------------------+
#property script_show_inputs
#include <BlackDragon/Recovery/RecoveryT164Reachability.mqh>

int g_pass=0, g_fail=0;
void Check(const string name,const bool cond)
{
   if(cond){g_pass++;return;}
   g_fail++;
   Print("FAIL: ",name);
}

void OnStart()
{
   Check("start0 requires1",Recovery_T164RequiredCoreCountPure(0)==1);
   Check("start7 requires8",Recovery_T164RequiredCoreCountPure(7)==8);
   Check("start13 requires14",Recovery_T164RequiredCoreCountPure(13)==14);
   Check("negative invalid",Recovery_T164RequiredCoreCountPure(-1)==-1);

   Check("Max8 Start7 reachable",Recovery_T164SideReachablePure(true,8,7));
   Check("Max8 Start8 unreachable",!Recovery_T164SideReachablePure(true,8,8));
   Check("Max8 Start13 unreachable",!Recovery_T164SideReachablePure(true,8,13));
   Check("disabled side ignored",Recovery_T164SideReachablePure(false,1,99));
   Check("zero max invalid enabled",!Recovery_T164SideReachablePure(true,0,0));

   Check("ACTIVE both valid",
         Recovery_T164ValidateReachabilityPure(recovery_ACTIVE,true,true,8,8,7));
   Check("ACTIVE buy invalid",
         !Recovery_T164ValidateReachabilityPure(recovery_ACTIVE,true,false,8,1,13));
   Check("ACTIVE sell invalid",
         !Recovery_T164ValidateReachabilityPure(recovery_ACTIVE,false,true,1,8,13));
   Check("ACTIVE disabled invalid side ignored",
         Recovery_T164ValidateReachabilityPure(recovery_ACTIVE,true,false,8,1,7));
   Check("OFF preserves legacy config",
         Recovery_T164ValidateReachabilityPure(recovery_OFF,true,true,1,1,99));
   Check("SHADOW remains observational",
         Recovery_T164ValidateReachabilityPure(recovery_SHADOW,true,true,1,1,99));

   Check("Overlap6 preempts required14",Recovery_T164OverlapMayPreemptPure(true,6,13));
   Check("Overlap8 preempts required14",Recovery_T164OverlapMayPreemptPure(true,8,13));
   Check("Overlap14 same threshold not preempt",!Recovery_T164OverlapMayPreemptPure(true,14,13));
   Check("Overlap15 after threshold no preempt",!Recovery_T164OverlapMayPreemptPure(true,15,13));
   Check("Overlap disabled no warning",!Recovery_T164OverlapMayPreemptPure(false,6,13));

   PrintFormat("Recovery T16.4 reachability tests: %d passed, %d failed",g_pass,g_fail);
   if(g_fail==0) Print("ALL GREEN — T16.4 reachability/Overlap boundary policy passed.");
}
