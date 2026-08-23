//+------------------------------------------------------------------+
//| RunT176HardeningTests.mq5 — T17.6 pure policy locks              |
//+------------------------------------------------------------------+
#property script_show_inputs
#include <BlackDragon/Recovery/RecoveryT16Config.mqh>
#include <BlackDragon/Recovery/RecoveryDca.mqh>

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
   Check("rebase raises BUILDING target after retained Hedge disappears",
         Recovery_T176RebasedGenerationTargetPure(18,97)==97);
   Check("rebase is add-only when computed target falls below live",
         Recovery_T176RebasedGenerationTargetPure(18,12)==18);
   Check("rebase clamps negative computed target to live",
         Recovery_T176RebasedGenerationTargetPure(18,-1)==18);
   Check("rebase allows zero only when both live/computed are zero",
         Recovery_T176RebasedGenerationTargetPure(0,0)==0);

   Check("staged attainable coverage uses hard cap",
         Near(Recovery_T17AttainableCoveragePercentPure(hedge_pyramid_BAC_COVERAGE,160.0,90.0),90.0));
   Check("plain ARCS attainable coverage keeps configured target",
         Near(Recovery_T17AttainableCoveragePercentPure(hedge_pyramid_TAT,160.0,90.0),160.0));
   Check("zero hard cap leaves configured target",
         Near(Recovery_T17AttainableCoveragePercentPure(hedge_pyramid_BAC_COVERAGE,160.0,0.0),160.0));

   Check("Hedge Pyramid cannot be enabled while Recovery is OFF",
         !Recovery_T17CrossInputsValidPure(recovery_OFF,
                                           hedge_pyramid_BAC_COVERAGE,
                                           false,0.0,100.0,100.0));
   Check("Recovery OFF with Hedge Pyramid OFF remains valid",
         Recovery_T17CrossInputsValidPure(recovery_OFF,
                                          hedge_pyramid_TAT,
                                          false,0.0,100.0,100.0));
   Check("post-Hedge DCA cannot demand unreachable staged coverage",
         !Recovery_T17CrossInputsValidPure(recovery_ACTIVE,
                                           hedge_pyramid_BAC_COVERAGE,
                                           true,100.0,160.0,90.0));
   Check("post-Hedge DCA coverage below staged cap is reachable",
         Recovery_T17CrossInputsValidPure(recovery_ACTIVE,
                                          hedge_pyramid_BAC_COVERAGE,
                                          true,80.0,160.0,90.0));
   Check("disabled post-Hedge DCA does not create false reachability failure",
         Recovery_T17CrossInputsValidPure(recovery_ACTIVE,
                                          hedge_pyramid_BAC_COVERAGE,
                                          false,150.0,160.0,90.0));

   string why="";
   Check("DCA min coverage above 100 is valid when Recovery is enabled",
         Recovery_ValidateDcaConfig(recovery_ACTIVE,150.0,0.0,why));
   why="";
   Check("negative DCA min coverage remains invalid",
         !Recovery_ValidateDcaConfig(recovery_ACTIVE,-1.0,0.0,why));

   Print("T17.6 hardening tests: ",g_pass," passed, ",g_fail," failed");
   if(g_fail==0) Print("ALL GREEN");
   else Print("TESTS FAILED");
}
