#property strict
#include <BlackDragon/ExecutionLayer.mqh>
#include <BlackDragon/Recovery/RecoveryT177HedgeLadder.mqh>

int g_pass=0,g_fail=0;
void T(const bool ok,const string name)
{
   if(ok) g_pass++;
   else { g_fail++; Print("FAIL: ",name); }
}

void OnStart()
{
   T(Recovery_T1716BrokerPartialStagePure(90,80,5,100,5,100),
     "exact admitted broker child continues");
   T(!Recovery_T1716BrokerPartialStagePure(90,80,5,110,5,100),
     "denominator rebase is not partial");
   T(!Recovery_T1716BrokerPartialStagePure(80,80,5,100,5,100),
     "stage boundary is not partial");
   T(!Recovery_T1716BrokerPartialStagePure(100,80,5,100,5,100),
     "completed stage is not partial");
   T(!Recovery_T1716BrokerPartialStagePure(90,80,6,100,5,100),
     "different stage is not partial");

   // Stateful owner counterexample: previously satisfied target 34 rebases to
   // 37 after Core ADD. Old stage authority must not bypass lock/gap.
   int admittedStage=6;
   long admittedTarget=34;
   long live=34;
   long previousTarget=31;
   long rebasedTarget=37;
   T(!Recovery_T1716BrokerPartialStagePure(live,previousTarget,6,
                                            rebasedTarget,admittedStage,
                                            admittedTarget),
     "Core ADD 0.02 invalidates same-stage target34 authority at target37");

   // economics-safe -> quiet BUILDING -> Overlap trim -> target refresh.
   // Clearing the marker makes the 68->72 refill a new admission.
   admittedStage=0;
   admittedTarget=0;
   T(!Recovery_T1716BrokerPartialStagePure(68,60,4,72,
                                            admittedStage,admittedTarget),
     "post-Overlap 68 to72 refill re-runs safety gates");
   admittedStage=4;
   admittedTarget=72;
   T(Recovery_T1716BrokerPartialStagePure(70,60,4,72,
                                           admittedStage,admittedTarget),
     "post-gate broker child 70 may finish target72");

   double threshold=Exec_RiskAddRecoveryThresholdPure(100.0);
   T(MathAbs(threshold-110.0)<1e-9,
     "capacity threshold uses ten percent hysteresis");
   T(Exec_RiskAddEmbargoBlocksPure(true,-10.0,threshold),
     "negative free margin blocks risk add");
   T(Exec_RiskAddEmbargoBlocksPure(true,100.0,threshold),
     "new bar alone does not clear capacity embargo");
   T(Exec_RiskAddEmbargoBlocksPure(true,109.99,threshold),
     "margin below hysteresis remains blocked");
   T(!Exec_RiskAddEmbargoBlocksPure(true,110.0,threshold),
     "margin recovery clears embargo");
   T(!Exec_RiskAddEmbargoBlocksPure(false,-1000.0,threshold),
     "inactive embargo permits admission");
   T(Exec_RiskAddEmbargoBlocksPure(true,1000.0,0.0),
     "unknown margin requirement fails closed");

   T(Recovery_T1716UnsafeGrowthEnvelopePure(
       recovery_ACTIVE,true,pyramid_TAI_KICH_HOAT,
       1000,1000,1000,0.0,0.0,false),
     "tester unbounded growth set raises advisory");
   T(!Recovery_T1716UnsafeGrowthEnvelopePure(
       recovery_ACTIVE,true,pyramid_TAI_KICH_HOAT,
       4,20,20,0.0,0.0,false),
     "bounded default-style add cap does not raise advisory");
   T(!Recovery_T1716UnsafeGrowthEnvelopePure(
       recovery_ACTIVE,true,pyramid_TAI_KICH_HOAT,
       1000,1000,1000,0.0,0.0,true),
     "enabled loss stop suppresses unbounded-envelope advisory");

   Print("T17.16 native rebase/capacity: ",g_pass,
         " passed, ",g_fail," failed");
   if(g_fail==0) Print("ALL GREEN");
   if(g_fail>0) ExpertRemove();
}
