//+------------------------------------------------------------------+
//| RunPyramidT17Tests.mq5 — T17 native pure-policy tests            |
//| Final exact-head checkpoint also triggers full T16 regression.   |
//+------------------------------------------------------------------+
#property script_show_inputs
#include <BlackDragon/Pyramid/PyramidConfig.mqh>
#include <BlackDragon/Recovery/RecoveryT16Config.mqh>

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
   Check("BUY favorable hit", Pyramid_FavorableGapHitPure(0,4000.0,4000.9,4001.0,1.0));
   Check("BUY favorable miss", !Pyramid_FavorableGapHitPure(0,4000.0,4000.8,4000.9,1.0));
   Check("SELL favorable hit", Pyramid_FavorableGapHitPure(1,4000.0,3999.0,3999.1,1.0));
   Check("SELL favorable miss", !Pyramid_FavorableGapHitPure(1,4000.0,3999.1,3999.2,1.0));

   Check("BUY LIFO peel hit", Pyramid_PeelHitPure(0,4001.0,4000.3,4000.4,0.7));
   Check("BUY LIFO peel miss", !Pyramid_PeelHitPure(0,4001.0,4000.31,4000.41,0.7));
   Check("SELL LIFO peel hit", Pyramid_PeelHitPure(1,3999.0,3999.6,3999.7,0.7));
   Check("SELL LIFO peel miss", !Pyramid_PeelHitPure(1,3999.0,3999.59,3999.69,0.7));

   Check("BUY favorable pips", Near(Pyramid_FavorablePipsPure(0,4000.0,4001.0,4001.1,0.1),10.0));
   Check("SELL favorable pips", Near(Pyramid_FavorablePipsPure(1,4000.0,3998.9,3999.0,0.1),10.0));
   Check("BUY room to TP", Near(Pyramid_RoomToTpPipsPure(0,4002.0,4001.4,4001.5,0.1),5.0));
   Check("SELL room to TP", Near(Pyramid_RoomToTpPipsPure(1,3998.0,3998.5,3998.6,0.1),5.0));

   Check("profit-funded cap", Near(Pyramid_RiskCapLotPure(20.0,30.0,100.0),0.06,1e-12));
   Check("risk cap percent clamps 100", Near(Pyramid_RiskCapLotPure(20.0,150.0,100.0),0.20,1e-12));
   Check("risk cap no profit zero", Pyramid_RiskCapLotPure(0.0,30.0,100.0)==0.0);
   Check("risk cap no budget zero", Pyramid_RiskCapLotPure(20.0,0.0,100.0)==0.0);

   Check("coverage master cap", Pyramid_EffectiveCoveragePure(115.0,100.0,115.0)==100.0);
   Check("coverage hard cap", Pyramid_EffectiveCoveragePure(100.0,115.0,80.0)==80.0);
   Check("coverage unchanged", Pyramid_EffectiveCoveragePure(55.0,100.0,100.0)==55.0);

   Check("ARCS layered raw 35 pct", Recovery_T16NewGenerationRawUnitsPure(ARCS_XEP_LOP,100,0,35.0)==35);
   Check("balanced raw subtract existing", Recovery_T16NewGenerationRawUnitsPure(HEDGE_CAN_BANG,100,35,55.0)==20);
   Check("balanced already covered zero", Recovery_T16NewGenerationRawUnitsPure(HEDGE_CAN_BANG,100,60,55.0)==0);
   Check("broker minimum clamp", Recovery_T166ClampPositiveGenerationUnitsPure(1,2)==2);
   Check("zero never invents hedge", Recovery_T166ClampPositiveGenerationUnitsPure(0,2)==0);

   Check("runtime hard cap OFF preserves configured target",
         Near(Recovery_T17RuntimeHedgePercentPure(hedge_pyramid_TAT,115.0,115.0,75.0),115.0));
   Check("runtime hard cap ON caps configured target",
         Near(Recovery_T17RuntimeHedgePercentPure(hedge_pyramid_BAC_COVERAGE,115.0,115.0,75.0),75.0));
   Check("runtime hard cap leaves explicit stage percent unchanged",
         Near(Recovery_T17RuntimeHedgePercentPure(hedge_pyramid_BAC_COVERAGE,55.0,115.0,75.0),55.0));

   string c=Pyramid_BuildComment(0,4);
   Check("role comment level", Pyramid_LevelFromComment(c)==4);
   Check("non pyramid comment rejected", Pyramid_LevelFromComment("EA Black Dragon|4")==-1);

   PrintFormat("Pyramid T17 tests: %d passed, %d failed",g_pass,g_fail);
   if(g_fail==0) Print("ALL GREEN — T17 Core/Recovery Pyramid pure policy passed.");
}
