//+------------------------------------------------------------------+
//| RunT177OverlapTests.mq5 — T17.7 C3 pure durable Overlap locks   |
//+------------------------------------------------------------------+
#property script_show_inputs
#include <BlackDragon/Overlap/OverlapT177Policy.mqh>

int g_pass=0, g_fail=0;
void Check(const string name,const bool cond)
{
   if(cond){g_pass++;return;}
   g_fail++;
   Print("FAIL: ",name);
}

void OnStart()
{
   Check("preleg accepts ratio+reserve",
         Overlap_T177PreLeg1EligiblePure(8,8,true,-100.0,110.0,3.0,5.0));
   Check("preleg rejects ratio",
         !Overlap_T177PreLeg1EligiblePure(8,8,true,-100.0,102.0,3.0,1.0));
   Check("preleg rejects reserve",
         !Overlap_T177PreLeg1EligiblePure(8,8,true,-100.0,105.0,3.0,10.0));
   Check("preleg rejects disabled",
         !Overlap_T177PreLeg1EligiblePure(8,8,false,-100.0,110.0,3.0,1.0));
   Check("preleg rejects invalid economics",
         !Overlap_T177PreLeg1EligiblePure(8,8,true,-100.0,110.0,3.0,DBL_MAX));

   Check("leg2 safe after actual fill",
         Overlap_T177Leg2SafePure(110.0,-100.0,5.0));
   Check("leg2 unsafe after adverse fill",
         !Overlap_T177Leg2SafePure(102.0,-100.0,5.0));
   Check("leg2 equality safe",
         Overlap_T177Leg2SafePure(105.0,-100.0,5.0));
   Check("leg2 invalid reserve waits",
         !Overlap_T177Leg2SafePure(200.0,-100.0,DBL_MAX));

   Check("pending observation",
         Overlap_T177SubmittedObservationPure(false,true,true,false)==overlap_T177_OBS_PENDING);
   Check("ticket gone confirmed",
         Overlap_T177SubmittedObservationPure(false,false,false,false)==overlap_T177_OBS_CONFIRMED);
   Check("restart live becomes reconcile",
         Overlap_T177SubmittedObservationPure(true,true,false,false)==overlap_T177_OBS_RECONCILE);
   Check("same-session rejection is not ambiguity",
         Overlap_T177SubmittedObservationPure(false,true,false,false)==overlap_T177_OBS_REJECTED);
   Check("reconcile dominates pending",
         Overlap_T177SubmittedObservationPure(false,true,true,true)==overlap_T177_OBS_RECONCILE);

   Check("idle does not block side",
         !Overlap_T177BlocksSidePure(overlap_T177_IDLE));
   Check("armed blocks side",
         Overlap_T177BlocksSidePure(overlap_T177_PAIR_ARMED));
   Check("leg2 wait blocks same side",
         Overlap_T177BlocksSidePure(overlap_T177_LEG2_WAIT_SAFE));
   Check("complete releases side",
         !Overlap_T177BlocksSidePure(overlap_T177_COMPLETE));

   Check("wait yields strategy",
         !Overlap_T177ConsumesStrategyTickPure(overlap_T177_DRIVE_WAIT));
   Check("no-effect yields strategy",
         !Overlap_T177ConsumesStrategyTickPure(overlap_T177_DRIVE_NO_EFFECT));
   Check("mutation consumes strategy",
         Overlap_T177ConsumesStrategyTickPure(overlap_T177_DRIVE_MUTATED));
   Check("pending consumes strategy",
         Overlap_T177ConsumesStrategyTickPure(overlap_T177_DRIVE_PENDING));
   Check("reconcile consumes strategy",
         Overlap_T177ConsumesStrategyTickPure(overlap_T177_DRIVE_RECONCILE));

   Check("leg1 state is submitted",
         Overlap_T177SubmittedStatePure(overlap_T177_LEG1_SUBMITTED));
   Check("leg2 state is submitted",
         Overlap_T177SubmittedStatePure(overlap_T177_LEG2_SUBMITTED));
   Check("wait state is not submitted",
         !Overlap_T177SubmittedStatePure(overlap_T177_LEG2_WAIT_SAFE));

   Print("T17.7 C3 Overlap tests: ",g_pass," passed, ",g_fail," failed");
   if(g_fail==0) Print("ALL GREEN");
   else Print("TESTS FAILED");
}
