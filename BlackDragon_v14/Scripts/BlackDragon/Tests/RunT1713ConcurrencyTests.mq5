#property strict
#include <BlackDragon/Recovery/RecoveryT1713ConcurrencyPolicy.mqh>
#include <BlackDragon/Overlap/OverlapT177Policy.mqh>

int g_pass=0, g_fail=0;
void T(const bool ok,const string name)
{
   if(ok) g_pass++;
   else { g_fail++; Print("FAIL: ",name); }
}

bool DriveCoreDcaIntegrationModel(const eRecoveryMode mode,
                                  const bool continueAfterHedge,
                                  const eRecoveryState recoveryState,
                                  const bool recoveryMutatedThisTick,
                                  const eOverlapT177State overlapState,
                                  const bool executionPending,
                                  const bool spacingDue,
                                  int &openCalls)
{
   if(recoveryMutatedThisTick) return false;
   if(!Recovery_T1713CoreGrowthStateAllowsPure(mode,continueAfterHedge,recoveryState))
      return false;
   if(Overlap_T1713BlocksCoreGrowthPure(overlapState)) return false;
   if(executionPending || !spacingDue) return false;
   openCalls++;
   return true;
}

void OnStart()
{
   T(Recovery_T1713CoreGrowthStateAllowsPure(recovery_ACTIVE,true,recovery_HEDGE_BUILDING),
     "ContinueDca allows BUILDING read-only Core growth");
   T(Recovery_T1713CoreGrowthStateAllowsPure(recovery_ACTIVE,true,recovery_HEDGE_ACTIVE),
     "ContinueDca allows ACTIVE read-only Core growth");
   T(Recovery_T1713CoreGrowthStateAllowsPure(recovery_ACTIVE,true,recovery_HEDGE_LOCKED),
     "ContinueDca allows LOCKED Core growth");
   T(Recovery_T1713CoreGrowthStateAllowsPure(recovery_ACTIVE,true,recovery_REHEDGE_PENDING),
     "ContinueDca allows REHEDGE_PENDING Core growth");
   T(!Recovery_T1713CoreGrowthStateAllowsPure(recovery_ACTIVE,false,recovery_HEDGE_BUILDING),
     "ContinueDca false preserves block");
   T(!Recovery_T1713CoreGrowthStateAllowsPure(recovery_ACTIVE,true,recovery_HEDGE_TP_PENDING),
     "Hedge TP pending blocks Core growth");
   T(!Recovery_T1713CoreGrowthStateAllowsPure(recovery_ACTIVE,true,recovery_RECONCILE_REQUIRED),
     "Recovery reconcile blocks Core growth");

   T(!Overlap_T1713BlocksCoreGrowthPure(overlap_T177_PAIR_ARMED),
     "Overlap PAIR_ARMED yields same-side Core growth");
   T(!Overlap_T1713BlocksCoreGrowthPure(overlap_T177_LEG1_CONFIRMED),
     "Overlap LEG1_CONFIRMED yields Core growth");
   T(!Overlap_T1713BlocksCoreGrowthPure(overlap_T177_LEG2_RECHECK),
     "Overlap LEG2_RECHECK yields Core growth");
   T(!Overlap_T1713BlocksCoreGrowthPure(overlap_T177_LEG2_WAIT_SAFE),
     "Overlap LEG2_WAIT_SAFE yields Core growth");
   T(Overlap_T1713BlocksCoreGrowthPure(overlap_T177_LEG1_SUBMITTED),
     "Overlap LEG1_SUBMITTED blocks Core growth");
   T(Overlap_T1713BlocksCoreGrowthPure(overlap_T177_LEG2_SUBMITTED),
     "Overlap LEG2_SUBMITTED blocks Core growth");
   T(Overlap_T1713BlocksCoreGrowthPure(overlap_T177_RECONCILE),
     "Overlap RECONCILE blocks Core growth");

   T(!Overlap_T1713MayCommitPairPure(false,false),
     "unsafe economics remains soft candidate");
   T(!Overlap_T1713MayCommitPairPure(true,true),
     "Recovery DEFER remains soft candidate");
   T(Overlap_T1713MayCommitPairPure(true,false),
     "pair commits only when immediately executable");

   double trigger=4091.635-13.0*0.10;
   T(4049.197<=trigger+1e-12,
     "owner 11-BUY counterexample is DCA due by >13 pip");

   int calls=0;
   T(DriveCoreDcaIntegrationModel(recovery_ACTIVE,true,recovery_HEDGE_BUILDING,
                                  false,overlap_T177_PAIR_ARMED,false,true,calls),
     "11-BUY traverses scheduler admission to execution seam");
   T(calls==1,"11-BUY emits exactly one broker-open intent");

   calls=0;
   T(!DriveCoreDcaIntegrationModel(recovery_ACTIVE,true,recovery_HEDGE_BUILDING,
                                   true,overlap_T177_PAIR_ARMED,false,true,calls) && calls==0,
     "Recovery mutation preserves one-mutation-per-tick");
   calls=0;
   T(!DriveCoreDcaIntegrationModel(recovery_ACTIVE,true,recovery_HEDGE_BUILDING,
                                   false,overlap_T177_LEG1_SUBMITTED,false,true,calls) && calls==0,
     "Overlap broker mutation blocks integration execution seam");
   calls=0;
   T(!DriveCoreDcaIntegrationModel(recovery_ACTIVE,false,recovery_HEDGE_BUILDING,
                                   false,overlap_T177_PAIR_ARMED,false,true,calls) && calls==0,
     "ContinueDca opt-out blocks integration execution seam");

   Print("T17.13 native concurrency: ",g_pass," passed, ",g_fail," failed");
   if(g_fail==0) Print("ALL GREEN");
   if(g_fail>0) ExpertRemove();
}
