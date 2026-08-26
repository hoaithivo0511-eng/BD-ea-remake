//+------------------------------------------------------------------+
//| RunRecoveryT165Tests.mq5 — T16.5 pure native policy tests        |
//+------------------------------------------------------------------+
#property script_show_inputs
#include <BlackDragon/Recovery/RecoveryT165Policy.mqh>

int g_pass=0, g_fail=0;
void Check(const string name,const bool cond)
{
   if(cond){g_pass++;return;}
   g_fail++;
   Print("FAIL: ",name);
}

void OnStart()
{
   Check("legacy core-only pctdiff would fire",
         Recovery_T165PctDiffHitPure(6.45,-2.19,3.5));
   double buyEconomic=Recovery_T165EconomicSideProfitPure(6.45,-1466.60);
   double sellEconomic=Recovery_T165EconomicSideProfitPure(-2.19,0.0);
   Check("economic buy includes Recovery hedge",
         MathAbs(buyEconomic+1460.15)<1e-9);
   Check("economic pctdiff does not fire",
         !Recovery_T165PctDiffHitPure(buyEconomic,sellEconomic,3.5));
   Check("economic magic net includes Recovery",
         MathAbs(Recovery_T165MagicNetPure(6.45,-2.19,-1466.60,0.0)+1462.34)<1e-9);
   Check("economic side helper",
         MathAbs(Recovery_T165EconomicSideProfitPure(10.0,-4.0)-6.0)<1e-9);

   Check("preflight failure waits",
         Recovery_T165CapacityDispositionPure(false,false,false)==RECOVERY_T165_CAPACITY_WAIT_NO_EFFECT);
   Check("explicit reject waits",
         Recovery_T165CapacityDispositionPure(true,false,false)==RECOVERY_T165_CAPACITY_WAIT_NO_EFFECT);
   Check("accepted executes",
         Recovery_T165CapacityDispositionPure(true,true,false)==RECOVERY_T165_CAPACITY_EXECUTE);
   Check("ambiguous reconciles",
         Recovery_T165CapacityDispositionPure(true,false,true)==RECOVERY_T165_CAPACITY_RECONCILE);
   Check("ambiguous dominates accepted",
         Recovery_T165CapacityDispositionPure(true,true,true)==RECOVERY_T165_CAPACITY_RECONCILE);

   Check("margin reserve exact",
         Recovery_T165MarginReserveAllowsPure(1000.0,250.0,750.0));
   Check("margin reserve above",
         Recovery_T165MarginReserveAllowsPure(1001.0,250.0,750.0));
   Check("margin reserve shortfall blocks",
         !Recovery_T165MarginReserveAllowsPure(999.0,250.0,750.0));
   Check("margin reserve no hedge",
         Recovery_T165MarginReserveAllowsPure(250.0,250.0,0.0));
   Check("margin reserve negative free invalid",
         !Recovery_T165MarginReserveAllowsPure(-1.0,0.0,0.0));
   Check("margin reserve negative component invalid",
         !Recovery_T165MarginReserveAllowsPure(100.0,-1.0,10.0));

   Check("wait heartbeat 900",
         Recovery_T165WaitLogSecondsPure(900)==900);
   Check("wait heartbeat zero",
         Recovery_T165WaitLogSecondsPure(0)==0);
   Check("wait heartbeat negative clamps zero",
         Recovery_T165WaitLogSecondsPure(-5)==0);
   Check("wait heartbeat max clamps one day",
         Recovery_T165WaitLogSecondsPure(999999)==86400);

   PrintFormat("Recovery T16.5 guard/margin/log tests: %d passed, %d failed",g_pass,g_fail);
   if(g_fail==0) Print("ALL GREEN — T16.5 scope/capacity/log policy passed.");
}
