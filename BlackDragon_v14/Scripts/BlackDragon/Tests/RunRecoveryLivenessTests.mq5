//+------------------------------------------------------------------+
//| RunRecoveryLivenessTests.mq5 — T16.3 native liveness policy      |
//+------------------------------------------------------------------+
#property script_show_inputs
#include <BlackDragon/Recovery/RecoveryT163Policy.mqh>
#include <BlackDragon/Recovery/RecoveryDca.mqh>
#include <BlackDragon/Recovery/RecoveryMutationPolicy.mqh>
#include <BlackDragon/Recovery/RecoveryLock.mqh>

int g_pass=0, g_fail=0;
void Check(const string name,const bool cond)
{
   if(cond){g_pass++;return;}
   g_fail++;
   Print("FAIL: ",name);
}

void OnStart()
{
   Check("deterministic lock wait yields",
         Recovery_T163DeferredLockYieldPure(true,true,false,false));
   Check("normal mutation does not yield",
         !Recovery_T163DeferredLockYieldPure(true,false,false,false));
   Check("pending modify does not yield",
         !Recovery_T163DeferredLockYieldPure(true,true,true,false));
   Check("ambiguous modify does not yield",
         !Recovery_T163DeferredLockYieldPure(true,true,false,true));
   Check("non-consumed path does not synthesize yield",
         !Recovery_T163DeferredLockYieldPure(false,true,false,false));

   Check("deferred scheduling view is REHEDGE_PENDING",
         Recovery_T163SchedulingStatePure(recovery_HEDGE_LOCK_PENDING,true,false)==recovery_REHEDGE_PENDING);
   Check("T7 considers REHEDGE_PENDING stable",
         Recovery_DcaPostHedgeStableState(recovery_REHEDGE_PENDING));
   Check("T8 still defers Overlap in REHEDGE_PENDING",
         Recovery_OverlapPolicyPure(recovery_REHEDGE_PENDING)==recovery_OVERLAP_DEFER);

   Check("G30 Max30 Core4 Hedge0 terminal",
         Recovery_T163MaxedNoHedgePure(30,30,4,0,true));
   Check("G31 forbidden",
         !Recovery_GenerationCanStartPure(30,30));
   Check("G29 may start G30",
         Recovery_GenerationCanStartPure(29,30));
   Check("maxed scheduling view is HEDGE_LOCKED",
         Recovery_T163SchedulingStatePure(recovery_PAUSE_SOFT,false,true)==recovery_HEDGE_LOCKED);
   Check("T7 allows HEDGE_LOCKED when Continue=true",
         Recovery_DcaStateAllows(recovery_ACTIVE,true,recovery_HEDGE_LOCKED));
   Check("T8 coordinates stable HEDGE_LOCKED",
         Recovery_OverlapPolicyPure(recovery_HEDGE_LOCKED)==recovery_OVERLAP_COORDINATE);
   Check("no Core means no terminal hold",
         !Recovery_T163MaxedNoHedgePure(30,30,0,0,true));
   Check("remaining Hedge means not maxed-no-hedge",
         !Recovery_T163MaxedNoHedgePure(30,30,4,1,true));
   Check("pre-Max is not terminal",
         !Recovery_T163MaxedNoHedgePure(29,30,4,0,true));
   Check("non-terminal phase is not terminal",
         !Recovery_T163MaxedNoHedgePure(30,30,4,0,false));

   PrintFormat("Recovery T16.3 liveness tests: %d passed, %d failed",g_pass,g_fail);
   if(g_fail==0) Print("ALL GREEN — T16.3 deferred-lock/max-generation liveness passed.");
}
