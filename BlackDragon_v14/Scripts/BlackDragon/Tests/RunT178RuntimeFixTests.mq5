//+------------------------------------------------------------------+
//| RunT178RuntimeFixTests.mq5 — T17.8 P1 runtime regression locks  |
//+------------------------------------------------------------------+
#property script_show_inputs
#include <BlackDragon/Recovery/RecoveryT178RuntimePolicy.mqh>

int g_pass=0,g_fail=0;
void Check(const string name,const bool ok)
{
   if(ok){g_pass++;return;}
   g_fail++;
   Print("FAIL: ",name);
}

void OnStart()
{
   Check("ACTIVE stable no-TP yields",
         Recovery_T178ActiveTpWaitNoMutationPure(true,true,70,70,70,false));
   Check("TP hit delegates",
         !Recovery_T178ActiveTpWaitNoMutationPure(true,true,70,70,70,true));
   Check("inactive delegates",
         !Recovery_T178ActiveTpWaitNoMutationPure(false,true,70,70,70,false));
   Check("invalid layer delegates",
         !Recovery_T178ActiveTpWaitNoMutationPure(true,false,70,70,70,false));
   Check("zero live delegates",
         !Recovery_T178ActiveTpWaitNoMutationPure(true,true,0,0,0,false));
   Check("opened mismatch delegates",
         !Recovery_T178ActiveTpWaitNoMutationPure(true,true,70,69,70,false));
   Check("remaining mismatch delegates",
         !Recovery_T178ActiveTpWaitNoMutationPure(true,true,70,70,69,false));

   Check("persistence-only consumed yields",
         Recovery_T178PersistenceOnlyYieldPure(true,false,false,false));
   Check("semantic mutation owns tick",
         !Recovery_T178PersistenceOnlyYieldPure(true,true,false,false));
   Check("pending owns tick",
         !Recovery_T178PersistenceOnlyYieldPure(true,false,true,false));
   Check("reconcile owns tick",
         !Recovery_T178PersistenceOnlyYieldPure(true,false,false,true));
   Check("non-consumed not overridden",
         !Recovery_T178PersistenceOnlyYieldPure(false,false,false,false));

   Check("REAL TP exact proof",
         Recovery_T178ExpectedCoreRealTpPure(true,true,true,true,
                                             4081.376,4081.370,0.02,true));
   Check("virtual TP mode rejected",
         !Recovery_T178ExpectedCoreRealTpPure(false,true,true,true,
                                              4081.376,4081.376,0.02,true));
   Check("configured TP off rejected",
         !Recovery_T178ExpectedCoreRealTpPure(true,false,true,true,
                                              4081.376,4081.376,0.02,true));
   Check("non-Core owner rejected",
         !Recovery_T178ExpectedCoreRealTpPure(true,true,false,true,
                                              4081.376,4081.376,0.02,true));
   Check("non-TP reason rejected",
         !Recovery_T178ExpectedCoreRealTpPure(true,true,true,false,
                                              4081.376,4081.376,0.02,true));
   Check("programmed TP missing rejected",
         !Recovery_T178ExpectedCoreRealTpPure(true,true,true,true,
                                              0.0,4081.376,0.02,true));
   Check("fill outside tolerance rejected",
         !Recovery_T178ExpectedCoreRealTpPure(true,true,true,true,
                                              4081.376,4081.500,0.02,true));
   Check("cohort mismatch rejected",
         !Recovery_T178ExpectedCoreRealTpPure(true,true,true,true,
                                              4081.376,4081.376,0.02,false));

   Check("pre-ownership REAL TP bypass",
         Recovery_T178RealTpDispositionPure(true,false)==RECOVERY_T178_REAL_TP_BYPASS_PREOWNERSHIP);
   Check("owned REAL TP coordinates full side",
         Recovery_T178RealTpDispositionPure(true,true)==RECOVERY_T178_REAL_TP_COORDINATE_FULL_SIDE);
   Check("unproven TP remains external",
         Recovery_T178RealTpDispositionPure(false,true)==RECOVERY_T178_REAL_TP_EXTERNAL);
   Check("enum bypass differs external",
         RECOVERY_T178_REAL_TP_BYPASS_PREOWNERSHIP!=RECOVERY_T178_REAL_TP_EXTERNAL);
   Check("enum coordinate differs bypass",
         RECOVERY_T178_REAL_TP_COORDINATE_FULL_SIDE!=RECOVERY_T178_REAL_TP_BYPASS_PREOWNERSHIP);

   Print("T17.8 runtime fix tests: ",g_pass," passed, ",g_fail," failed");
   if(g_fail==0) Print("ALL GREEN");
   else Print("TESTS FAILED");
}
