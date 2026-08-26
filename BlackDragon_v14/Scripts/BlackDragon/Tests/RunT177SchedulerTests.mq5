//+------------------------------------------------------------------+
//| RunT177SchedulerTests.mq5 — T17.7 C1 scheduler policy locks      |
//+------------------------------------------------------------------+
#property script_show_inputs
#include <BlackDragon/Recovery/RecoveryT177Scheduler.mqh>

int g_pass=0, g_fail=0;
void Check(const string name,const bool cond)
{
   if(cond){g_pass++;return;}
   g_fail++;
   Print("FAIL: ",name);
}

void OnStart()
{
   Check("no-effect does not consume Strategy tick",
         !Recovery_T177ConsumesStrategyTickPure(RECOVERY_DRIVE_NO_EFFECT));
   Check("WAIT does not consume Strategy tick",
         !Recovery_T177ConsumesStrategyTickPure(RECOVERY_DRIVE_WAIT));
   Check("mutation consumes Strategy tick",
         Recovery_T177ConsumesStrategyTickPure(RECOVERY_DRIVE_MUTATED));
   Check("pending execution consumes Strategy tick",
         Recovery_T177ConsumesStrategyTickPure(RECOVERY_DRIVE_PENDING));
   Check("reconcile consumes Strategy tick",
         Recovery_T177ConsumesStrategyTickPure(RECOVERY_DRIVE_RECONCILE));

   Check("legacy consumed with no semantic effect is WAIT",
         Recovery_T177ClassifyDrivePure(true,false,false,false)==RECOVERY_DRIVE_WAIT);
   Check("semantic change is mutation",
         Recovery_T177ClassifyDrivePure(true,true,false,false)==RECOVERY_DRIVE_MUTATED);
   Check("pending outranks semantic change",
         Recovery_T177ClassifyDrivePure(true,true,true,false)==RECOVERY_DRIVE_PENDING);
   Check("reconcile outranks pending",
         Recovery_T177ClassifyDrivePure(true,true,true,true)==RECOVERY_DRIVE_RECONCILE);
   Check("semantic change is mutation even when legacy bool is false",
         Recovery_T177ClassifyDrivePure(false,true,false,false)==RECOVERY_DRIVE_MUTATED);
   Check("legacy no-consume without change stays no-effect",
         Recovery_T177ClassifyDrivePure(false,false,false,false)==RECOVERY_DRIVE_NO_EFFECT);

   Print("T17.7 C1 scheduler tests: ",g_pass," passed, ",g_fail," failed");
   if(g_fail==0) Print("ALL GREEN");
   else Print("TESTS FAILED");
}
