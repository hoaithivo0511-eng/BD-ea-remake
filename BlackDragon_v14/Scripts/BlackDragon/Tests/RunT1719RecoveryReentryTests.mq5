//+------------------------------------------------------------------+
//| RunT1719RecoveryReentryTests.mq5 — terminal re-entry pure gates |
//+------------------------------------------------------------------+
#property script_show_inputs
#include <BlackDragon/Recovery/RecoveryT1719ReentryPolicy.mqh>

int g_pass=0,g_fail=0;
void Check(const string name,const bool ok)
{
   if(ok){g_pass++;return;}
   g_fail++;
   Print("FAIL: ",name);
}

void OnStart()
{
   Check("positive cash",Recovery_T1719PositiveChainPure(12.5,1e-8));
   Check("zero cash accepted",Recovery_T1719PositiveChainPure(0.0,1e-8));
   Check("rounding epsilon accepted",Recovery_T1719PositiveChainPure(-5e-9,1e-8));
   Check("negative chain rejected",!Recovery_T1719PositiveChainPure(-0.01,1e-8));

   Check("eligible terminal",Recovery_T1719TerminalEligiblePure(true,3,3,185,0,8.2,1e-8,0,2));
   Check("exact ownership required",!Recovery_T1719TerminalEligiblePure(false,3,3,185,0,8.2,1e-8,0,2));
   Check("terminal generation required",!Recovery_T1719TerminalEligiblePure(true,2,3,185,0,8.2,1e-8,0,2));
   Check("core required",!Recovery_T1719TerminalEligiblePure(true,3,3,0,0,8.2,1e-8,0,2));
   Check("all hedge must close",!Recovery_T1719TerminalEligiblePure(true,3,3,185,1,8.2,1e-8,0,2));
   Check("positive aggregate required",!Recovery_T1719TerminalEligiblePure(true,3,3,185,0,-8.2,1e-8,0,2));
   Check("zero disables",!Recovery_T1719TerminalEligiblePure(true,3,3,185,0,8.2,1e-8,0,0));
   Check("outer cap enforced",!Recovery_T1719TerminalEligiblePure(true,3,3,185,0,8.2,1e-8,2,2));

   Check("buy reset below boundary waits",!Recovery_T1719ResetHitPure(recovery_CORE_BUY,1000,1008,1009,10));
   Check("buy reset exact Ask boundary",Recovery_T1719ResetHitPure(recovery_CORE_BUY,1000,1009,1010,10));
   Check("sell reset above boundary waits",!Recovery_T1719ResetHitPure(recovery_CORE_SELL,1000,991,992,10));
   Check("sell reset exact Bid boundary",Recovery_T1719ResetHitPure(recovery_CORE_SELL,1000,990,991,10));
   Check("zero reset buffer invalid",!Recovery_T1719ResetHitPure(recovery_CORE_BUY,1000,1000,1000,0));

   Check("buy return exact Bid anchor",Recovery_T1719ReturnHitPure(recovery_CORE_BUY,1000,1000,1001));
   Check("buy return above waits",!Recovery_T1719ReturnHitPure(recovery_CORE_BUY,1000,1001,1002));
   Check("sell return exact Ask anchor",Recovery_T1719ReturnHitPure(recovery_CORE_SELL,1000,999,1000));
   Check("sell return below waits",!Recovery_T1719ReturnHitPure(recovery_CORE_SELL,1000,998,999));

   Check("WAIT blocks DCA",Recovery_T1719BlocksCoreDcaPure(RECOVERY_REENTRY_WAIT_RESET));
   Check("ARMED blocks DCA",Recovery_T1719BlocksCoreDcaPure(RECOVERY_REENTRY_ARMED));
   Check("WAIT allows Pyramid ADD",!Recovery_T1719BlocksCorePyramidAddPure(RECOVERY_REENTRY_WAIT_RESET));
   Check("ARMED allows Pyramid ADD",!Recovery_T1719BlocksCorePyramidAddPure(RECOVERY_REENTRY_ARMED));
   Check("WAIT bypasses legacy pause-state gate",Recovery_T1719AllowsCorePyramidAddPure(RECOVERY_REENTRY_WAIT_RESET));
   Check("ARMED bypasses legacy pause-state gate",Recovery_T1719AllowsCorePyramidAddPure(RECOVERY_REENTRY_ARMED));
   Check("trigger blocks both growth paths",
         Recovery_T1719BlocksCoreDcaPure(RECOVERY_REENTRY_TRIGGER_PENDING) &&
         Recovery_T1719BlocksCorePyramidAddPure(RECOVERY_REENTRY_TRIGGER_PENDING));
   Check("in-cycle defers existing policy",
         !Recovery_T1719BlocksCoreDcaPure(RECOVERY_REENTRY_IN_CYCLE) &&
         !Recovery_T1719BlocksCorePyramidAddPure(RECOVERY_REENTRY_IN_CYCLE));
   Check("exhausted blocks growth",
         Recovery_T1719BlocksCoreDcaPure(RECOVERY_REENTRY_EXHAUSTED) &&
         Recovery_T1719BlocksCorePyramidAddPure(RECOVERY_REENTRY_EXHAUSTED));
   Check("WAIT keeps risk-reducing Peel",Recovery_T1719AllowsCorePyramidPeelPure(RECOVERY_REENTRY_WAIT_RESET));
   Check("first terminal waits reset",Recovery_T1719TerminalPhasePure(0,2)==RECOVERY_REENTRY_WAIT_RESET);
   Check("cap terminal exhausted",Recovery_T1719TerminalPhasePure(2,2)==RECOVERY_REENTRY_EXHAUSTED);

   Print("T17.19 Recovery re-entry tests: ",g_pass," passed, ",g_fail," failed");
   if(g_fail==0) Print("ALL GREEN");
   else Print("TESTS FAILED");
}
