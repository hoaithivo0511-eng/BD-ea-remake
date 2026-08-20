//+------------------------------------------------------------------+
//| RunRecoveryT166Tests.mq5 — T16.6 broker-min native policy tests |
//+------------------------------------------------------------------+
#property script_show_inputs
#include <BlackDragon/Recovery/RecoveryT16Config.mqh>
#include <BlackDragon/Recovery/RecoveryExit.mqh>

int g_pass=0, g_fail=0;
void Check(const string name,const bool cond)
{
   if(cond){g_pass++;return;}
   g_fail++;
   Print("FAIL: ",name);
}

void OnStart()
{
   Check("zero raw does not invent Hedge",
         Recovery_T166ClampPositiveGenerationUnitsPure(0,2)==0);
   Check("sub-min raw clamps to broker minimum",
         Recovery_T166ClampPositiveGenerationUnitsPure(1,2)==2);
   Check("exact broker minimum unchanged",
         Recovery_T166ClampPositiveGenerationUnitsPure(2,2)==2);
   Check("above broker minimum unchanged",
         Recovery_T166ClampPositiveGenerationUnitsPure(5,2)==5);
   Check("balanced raw deficit reproduces five units",
         Recovery_T16NewGenerationRawUnitsPure(HEDGE_CAN_BANG,80,87,115.0)==5);
   Check("balanced raw five clamps to min ten",
         Recovery_T166ClampPositiveGenerationUnitsPure(
            Recovery_T16NewGenerationRawUnitsPure(HEDGE_CAN_BANG,80,87,115.0),10)==10);

   Check("active56 pct15 closes8",
         Recovery_T166ExecutablePartialCloseUnitsPure(56,15.0,1)==8);
   Check("active45 pct15 closes6",
         Recovery_T166ExecutablePartialCloseUnitsPure(45,15.0,1)==6);
   Check("active7 pct15 closes1",
         Recovery_T166ExecutablePartialCloseUnitsPure(7,15.0,1)==1);
   Check("active6 pct15 closes1",
         Recovery_T166ExecutablePartialCloseUnitsPure(6,15.0,1)==1);
   Check("G7 active5 pct15 closes1",
         Recovery_T166ExecutablePartialCloseUnitsPure(5,15.0,1)==1);
   Check("one-min layer full closes",
         Recovery_T166ExecutablePartialCloseUnitsPure(1,15.0,1)==1);
   Check("illegal remainder reduces to legal close",
         Recovery_T166ExecutablePartialCloseUnitsPure(25,90.0,10)==15);
   Check("no legal partial full closes tiny layer",
         Recovery_T166ExecutablePartialCloseUnitsPure(15,15.0,10)==15);
   Check("illegal live exposure below min stays fail-closed",
         Recovery_T166ExecutablePartialCloseUnitsPure(9,15.0,10)==0);
   Check("100 percent remains full close",
         Recovery_T166ExecutablePartialCloseUnitsPure(5,100.0,1)==5);

   PrintFormat("Recovery T16.6 broker-min tests: %d passed, %d failed",g_pass,g_fail);
   if(g_fail==0) Print("ALL GREEN — T16.6 broker-min generation/partial-close policy passed.");
}
