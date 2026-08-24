//+------------------------------------------------------------------+
//| RunT177AnchorTests.mq5 — T17.7 C2 pure anchor policy locks       |
//+------------------------------------------------------------------+
#property script_show_inputs
#include <BlackDragon/Pyramid/PyramidAnchorT177.mqh>

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
   Check("DYNAMIC anchor mode valid",
         Pyramid_T177AnchorModeValid(pyramid_anchor_DYNAMIC));
   Check("FIRST_CORE_CUMULATIVE anchor mode valid",
         Pyramid_T177AnchorModeValid(pyramid_anchor_FIRST_CORE_CUMULATIVE));
   Check("invalid anchor mode rejected",
         !Pyramid_T177AnchorModeValid((eCorePyramidAnchorMode)99));

   double d[];
   ArrayResize(d,3);
   d[0]=25.0; d[1]=35.0; d[2]=38.0;
   Check("cumulative L1 = 25",
         Near(Pyramid_T177CumulativeDistancePure(d,1),25.0));
   Check("cumulative L2 = 60",
         Near(Pyramid_T177CumulativeDistancePure(d,2),60.0));
   Check("cumulative L3 = 98",
         Near(Pyramid_T177CumulativeDistancePure(d,3),98.0));
   Check("cumulative L4 repeats last = 136",
         Near(Pyramid_T177CumulativeDistancePure(d,4),136.0));
   Check("cumulative L5 repeats last = 174",
         Near(Pyramid_T177CumulativeDistancePure(d,5),174.0));

   // Pure helpers deliberately use the stable direction contract: 0=BUY,
   // 1=SELL. Keep this standalone script independent of Strategy-only aliases.
   Check("BUY first-core trigger symmetric",
         Near(Pyramid_T177FirstCoreTriggerPricePure(0,2000.0,98.0),2098.0));
   Check("SELL first-core trigger symmetric",
         Near(Pyramid_T177FirstCoreTriggerPricePure(1,2000.0,98.0),1902.0));
   Check("BUY equality hits cumulative target",
         Pyramid_T177FirstCoreGapHitPure(0,2000.0,2097.9,2098.0,98.0));
   Check("BUY below cumulative target waits",
         !Pyramid_T177FirstCoreGapHitPure(0,2000.0,2097.8,2097.9,98.0));
   Check("SELL equality hits cumulative target",
         Pyramid_T177FirstCoreGapHitPure(1,2000.0,1902.0,1902.1,98.0));
   Check("SELL above cumulative target waits",
         !Pyramid_T177FirstCoreGapHitPure(1,2000.0,1902.1,1902.2,98.0));

   Print("T17.7 C2 anchor tests: ",g_pass," passed, ",g_fail," failed");
   if(g_fail==0) Print("ALL GREEN");
   else Print("TESTS FAILED");
}
