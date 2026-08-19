//+------------------------------------------------------------------+
//| RunRecoveryArcsTests.mq5 — T16 native pure ARCS policy tests     |
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
   Check("25% Core100 ->25", Recovery_T16PercentUnitsPure(100,25.0)==25);
   Check("50% Core100 ->50", Recovery_T16PercentUnitsPure(100,50.0)==50);
   Check("80% Core100 ->80", Recovery_T16PercentUnitsPure(100,80.0)==80);
   Check("100% Core100 ->100",Recovery_T16PercentUnitsPure(100,100.0)==100);
   Check("120% Core100 ->120",Recovery_T16PercentUnitsPure(100,120.0)==120);
   Check("150% Core75 floors112",Recovery_T16PercentUnitsPure(75,150.0)==112);
   Check("33% Core75 floors24",Recovery_T16PercentUnitsPure(75,33.0)==24);

   Check("balance Core75 retained50 opens25",
         Recovery_T16NewGenerationUnitsPure(HEDGE_CAN_BANG,75,50,100.0)==25);
   Check("ARCS Core75 retained50 opens75",
         Recovery_T16NewGenerationUnitsPure(ARCS_XEP_LOP,75,50,100.0)==75);
   Check("ARCS 120pct Core75 opens90",
         Recovery_T16NewGenerationUnitsPure(ARCS_XEP_LOP,75,50,120.0)==90);
   Check("ARCS ignores retained overhedge",
         Recovery_T16NewGenerationUnitsPure(ARCS_XEP_LOP,75,100,100.0)==75);

   // Canonical source-of-truth sequence after G1=1.00 reaches TP.
   long g1Close=Recovery_PartialCloseTargetUnits(100,50.0,1);
   long g1Remain=100-g1Close;
   long coreRemain=75; // owner example: +250c funds 0.25 of Core 1.00
   long g2=Recovery_T16NewGenerationUnitsPure(ARCS_XEP_LOP,coreRemain,g1Remain,100.0);
   Check("oracle G1 partial50",g1Close==50);
   Check("oracle G1 retained50",g1Remain==50);
   Check("oracle G2 is75 not deficit25",g2==75);
   Check("oracle total Hedge125",g1Remain+g2==125);
   Check("oracle net SELL50",g1Remain+g2-coreRemain==50);

   // Active-generation TP scope: G2=.75 => 50% floors .37. It must not use
   // aggregate G1 .50 + G2 .75 (=1.25 => .62).
   Check("active G2 partial50 floors37",
         Recovery_PartialCloseTargetUnits(75,50.0,1)==37);
   Check("aggregate forbidden comparison is62",
         Recovery_PartialCloseTargetUnits(125,50.0,1)==62);

   Check("SELL hedge virtual SL arms above Ask",
         Recovery_T16VirtualSlArmingValidPure(recovery_CORE_BUY,4190.0,4190.1,4194.7));
   Check("SELL hedge virtual SL not early",
         !Recovery_T16VirtualSlHitPure(recovery_CORE_BUY,4194.5,4194.6,4194.7));
   Check("SELL hedge virtual SL hit at Ask",
         Recovery_T16VirtualSlHitPure(recovery_CORE_BUY,4194.6,4194.7,4194.7));
   Check("BUY hedge virtual SL arms below Bid",
         Recovery_T16VirtualSlArmingValidPure(recovery_CORE_SELL,4209.9,4210.0,4205.3));
   Check("BUY hedge virtual SL hit at Bid",
         Recovery_T16VirtualSlHitPure(recovery_CORE_SELL,4205.3,4205.4,4205.3));

   double sellGlobal=0.0;
   sellGlobal=Recovery_T16GlobalSlFoldPure(recovery_CORE_BUY,sellGlobal,4194.7);
   sellGlobal=Recovery_T16GlobalSlFoldPure(recovery_CORE_BUY,sellGlobal,4189.7);
   sellGlobal=Recovery_T16GlobalSlFoldPure(recovery_CORE_BUY,sellGlobal,4184.7);
   Check("SELL Global SL chooses lowest all-layer-safe target",
         MathAbs(sellGlobal-4184.7)<1e-9);

   double buyGlobal=0.0;
   buyGlobal=Recovery_T16GlobalSlFoldPure(recovery_CORE_SELL,buyGlobal,4205.3);
   buyGlobal=Recovery_T16GlobalSlFoldPure(recovery_CORE_SELL,buyGlobal,4210.3);
   Check("BUY Global SL chooses highest all-layer-safe target",
         MathAbs(buyGlobal-4210.3)<1e-9);

   PrintFormat("Recovery T16 ARCS tests: %d passed, %d failed",g_pass,g_fail);
   if(g_fail==0) Print("ALL GREEN — T16 ARCS stacked sizing/SL policy passed.");
}
