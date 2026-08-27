#property strict
#include <BlackDragon/Recovery/RecoveryT1714InterleavePolicy.mqh>
#include <BlackDragon/StrategyT1714GuardPolicy.mqh>

int g_pass=0, g_fail=0;
void T(const bool ok,const string name)
{
   if(ok) g_pass++;
   else { g_fail++; Print("FAIL: ",name); }
}

void OnStart()
{
   long batch[12]={5,2,2,18,6,11,9,11,10,17,17,26};
   long proven=0;
   for(int i=0;i<12;i++) proven+=batch[i];
   T(proven==134,"twelve exact broker-SL deals total 134 units");
   T(Recovery_T1714LayerRefreshPure(134,0,proven)==recovery_T1714_REFRESH_APPLY,
     "exact protective decrease is applied before Overlap validation");
   T(Recovery_T1714LayerRefreshPure(0,0,proven)==recovery_T1714_REFRESH_UNCHANGED,
     "duplicate callback refresh is idempotent");
   T(Recovery_T1714LayerRefreshPure(134,0,133)==recovery_T1714_REFRESH_RECONCILE,
     "partial proof remains fail-closed");
   T(Recovery_T1714LayerRefreshPure(134,0,135)==recovery_T1714_REFRESH_RECONCILE,
     "over-counted proof remains fail-closed");
   T(Recovery_T1714LayerRefreshPure(134,135,0)==recovery_T1714_REFRESH_RECONCILE,
     "volume increase remains fail-closed");
   T(Recovery_T1714LayerRefreshPure(134,134,0)==recovery_T1714_REFRESH_UNCHANGED,
     "unchanged exposure is a no-op");

   T(Strategy_T1714AccountGuardPreemptsRecoveryPure(GUARD_CLOSE_ACCOUNT,true),
     "account MoneyGuard preempts Recovery reconcile hold");
   T(!Strategy_T1714AccountGuardPreemptsRecoveryPure(GUARD_CLOSE_BUY,true),
     "BUY guard does not bypass side coordination");
   T(!Strategy_T1714AccountGuardPreemptsRecoveryPure(GUARD_CLOSE_MAGIC,true),
     "MAGIC guard does not bypass scoped coordination");
   T(!Strategy_T1714AccountGuardPreemptsRecoveryPure(GUARD_CLOSE_ACCOUNT,false),
     "idle Recovery needs no preemption");

   Print("T17.14 native runtime: ",g_pass," passed, ",g_fail," failed");
   if(g_fail==0) Print("ALL GREEN");
   if(g_fail>0) ExpertRemove();
}
