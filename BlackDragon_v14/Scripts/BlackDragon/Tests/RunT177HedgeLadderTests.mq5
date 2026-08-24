//+------------------------------------------------------------------+
//| RunT177HedgeLadderTests.mq5 — T17.7 C4 pure Hedge ladder locks  |
//+------------------------------------------------------------------+
#property script_show_inputs
#include <BlackDragon/Recovery/RecoveryT177HedgeLadder.mqh>

int g_pass=0, g_fail=0;
void Check(const string name,const bool cond)
{
   if(cond){g_pass++;return;}
   g_fail++;
   Print("FAIL: ",name);
}
bool Near(const double a,const double b,const double eps=1e-9)
{
   return MathAbs(a-b)<=eps;
}

void OnStart()
{
   Check("final 160 capped to 90",
         Near(Recovery_T177EffectiveFinalCoveragePercentPure(160.0,90.0),90.0));
   Check("zero cap leaves requested final",
         Near(Recovery_T177EffectiveFinalCoveragePercentPure(160.0,0.0),160.0));
   Check("core42 80pct floors33",Recovery_T177CoverageTotalUnitsPure(42,80.0)==33);
   Check("core42 81pct floors34",Recovery_T177CoverageTotalUnitsPure(42,81.0)==34);
   Check("core42 82pct floors34",Recovery_T177CoverageTotalUnitsPure(42,82.0)==34);
   Check("core42 85pct floors35",Recovery_T177CoverageTotalUnitsPure(42,85.0)==35);

   double cov[]; ArrayResize(cov,4);
   cov[0]=80.0; cov[1]=81.0; cov[2]=82.0; cov[3]=85.0;
   double gaps[]; ArrayResize(gaps,3);
   gaps[0]=10.0; gaps[1]=10.0; gaps[2]=15.0;
   SRecoveryT177HedgeStage plan[];
   int n=Recovery_T177BuildExecutableHedgeLadderPure(cov,gaps,42,0,1,plan);
   Check("80-81-82-85 dedups to 3 executable stages",n==3);
   Check("first executable stage keeps source80",n==3&&plan[0].sourceIndex==0&&plan[0].generationTargetUnits==33);
   Check("duplicate82 keeps first81 target",n==3&&plan[1].sourceIndex==1&&plan[1].generationTargetUnits==34);
   Check("final executable stage is85 target35",n==3&&plan[2].sourceIndex==3&&plan[2].generationTargetUnits==35);
   Check("gap80to81 remains10",n==3&&Near(plan[1].gapFromPreviousPips,10.0));
   Check("skipped82 remaps gap81to85 as25",n==3&&Near(plan[2].gapFromPreviousPips,25.0));
   Check("effective85 stage is83.333pct",n==3&&Near(plan[2].effectiveCoverage,83.3333333333,1e-6));

   SRecoveryT177HedgeStage retainedPlan[];
   int rn=Recovery_T177BuildExecutableHedgeLadderPure(cov,gaps,42,33,1,retainedPlan);
   Check("already-covered leading stage gives first new gap0",
         rn>=1&&retainedPlan[0].sourceIndex==1&&Near(retainedPlan[0].gapFromPreviousPips,0.0));
   Check("retained path still dedups82",
         rn==2&&retainedPlan[0].sourceIndex==1&&retainedPlan[1].sourceIndex==3);
   Check("retained duplicate gap to85 stays25",
         rn==2&&Near(retainedPlan[1].gapFromPreviousPips,25.0));

   Check("final raw core108 retained30 at90 is67",
         Recovery_T177FinalGenerationRawUnitsPure(108,30,90.0)==67);
   Check("broker min may not inflate beyond final cap",
         Recovery_T177ExecutableGenerationTargetPure(100,0,1.0,2,1)==0);
   double tinyCov[]; ArrayResize(tinyCov,2); tinyCov[0]=0.5; tinyCov[1]=1.0;
   double tinyGap[]; ArrayResize(tinyGap,1); tinyGap[0]=10.0;
   SRecoveryT177HedgeStage tinyPlan[];
   Check("unexecutable final below broker min produces no stage",
         Recovery_T177BuildExecutableHedgeLadderPure(tinyCov,tinyGap,100,0,2,tinyPlan)==0);
   Check("executable target never exceeds final raw",
         Recovery_T177ExecutableGenerationTargetPure(42,0,82.0,1,35)<=35);

   Print("T17.7 C4 Hedge ladder tests: ",g_pass," passed, ",g_fail," failed");
   if(g_fail==0) Print("ALL GREEN");
   else Print("TESTS FAILED");
}
