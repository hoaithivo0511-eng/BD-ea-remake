#property script_show_inputs
#include <BlackDragon/Config.mqh>
#include <BlackDragon/Types.mqh>
#include <BlackDragon/GridEngine.mqh>
#include <BlackDragon/BasketManager.mqh>
#include <BlackDragon/ExecutionLayer.mqh>
#include <BlackDragon/Recovery/RecoveryMath.mqh>

int g_t1710_pass = 0;
int g_t1710_fail = 0;

void T1710Check(const string name, const bool ok)
{
   if(ok) { g_t1710_pass++; return; }
   g_t1710_fail++;
   Print("FAIL: ", name);
}

void T1710Eq(const string name, const double got, const double want,
             const double eps=1e-10)
{
   T1710Check(name, MathAbs(got-want) <= eps);
}

void OnStart()
{
   T1710Eq("XAU 3d pip", Unit_PipSizePure(true, 0.001, 3), 0.10);
   T1710Eq("XAU 2d pip", Unit_PipSizePure(true, 0.01, 2), 0.10);
   T1710Eq("FX 5d pip", Unit_PipSizePure(false, 0.00001, 5), 0.00010);
   T1710Eq("FX 4d pip", Unit_PipSizePure(false, 0.00010, 4), 0.00010);
   T1710Check("XAU scale 3d", Unit_LegacyPointScalePure(true, 0.001, true)==10);
   T1710Check("XAU scale 2d", Unit_LegacyPointScalePure(true, 0.01, true)==1);
   T1710Check("AutoGold off", Unit_LegacyPointScalePure(true, 0.001, false)==1);

   double xau3=Unit_LegacyPointSizePure(true,0.001,true);
   double xau2=Unit_LegacyPointSizePure(true,0.01,true);
   double fx5=Unit_LegacyPointSizePure(false,0.00001,true);
   double fx4=Unit_LegacyPointSizePure(false,0.0001,true);
   T1710Eq("legacy XAU references equal",xau3,xau2);
   T1710Eq("XAU3 legacy TP300",Unit_ConfigDistancePricePure(300,unit_LEGACY_COMPAT,xau3,.1),3.0);
   T1710Eq("XAU2 legacy TP300",Unit_ConfigDistancePricePure(300,unit_LEGACY_COMPAT,xau2,.1),3.0);
   T1710Eq("XAU unified TP300",Unit_ConfigDistancePricePure(300,unit_PIP_UNIFIED,xau3,.1),30.0);
   T1710Eq("FX5 legacy TP300",Unit_ConfigDistancePricePure(300,unit_LEGACY_COMPAT,fx5,.0001),.003);
   T1710Eq("FX5 unified TP300",Unit_ConfigDistancePricePure(300,unit_PIP_UNIFIED,fx5,.0001),.03);
   T1710Eq("FX4 legacy TP300",Unit_ConfigDistancePricePure(300,unit_LEGACY_COMPAT,fx4,.0001),.03);

   T1710Eq("XAU3 legacy DCA20",Unit_DcaDistancePricePure(20,unit_LEGACY_COMPAT,xau3,.1),2.0);
   T1710Eq("XAU2 legacy DCA20",Unit_DcaDistancePricePure(20,unit_LEGACY_COMPAT,xau2,.1),2.0);
   T1710Eq("XAU unified DCA20",Unit_DcaDistancePricePure(20,unit_PIP_UNIFIED,xau3,.1),2.0);
   T1710Eq("FX5 legacy DCA20",Unit_DcaDistancePricePure(20,unit_LEGACY_COMPAT,fx5,.0001),.002);
   T1710Eq("FX4 legacy bridge",Unit_DcaDistancePricePure(20,unit_LEGACY_COMPAT,fx4,.0001),.02);
   T1710Eq("FX4 unified correction",Unit_DcaDistancePricePure(20,unit_PIP_UNIFIED,fx4,.0001),.002);

   T1710Check("exact broker points",Unit_PriceToBrokerPointsCeilPure(.03,.001)==30);
   T1710Check("outward broker points",Unit_PriceToBrokerPointsCeilPure(.0301,.001)==31);
   T1710Check("zero broker points",Unit_PriceToBrokerPointsCeilPure(0,.001)==0);
   T1710Eq("tick cash shift",Unit_CostShiftPricePure(-10,1,10,.25),-.25);
   T1710Eq("basket tick-size BE",Basket_Breakeven(1.0,1.0,-10,10,.25,true),1.25);
   T1710Eq("tick-value guard",Unit_CostShiftPricePure(-10,1,0,.25),0);
   T1710Eq("tick-size guard",Unit_CostShiftPricePure(-10,1,10,0),0);

   T1710Eq("Recovery central pip",Recovery_PipSizePure(true,.001,3),Unit_PipSizePure(true,.001,3));
   T1710Eq("Recovery central price",Recovery_PipsToPricePure(50,true,.001,3),5.0);
   T1710Check("Recovery central ticks",Recovery_PipsToTicksPure(5,true,.001,3,.01)==50);

   SUnitProfile p; string why="";
   T1710Check("valid profile",Unit_BuildProfilePure(false,.00001,5,.00001,true,p,why));
   T1710Check("invalid point fails",!Unit_BuildProfilePure(false,0,5,.00001,true,p,why));
   T1710Check("invalid tick fails",!Unit_BuildProfilePure(false,.00001,5,0,true,p,why));

   double gaps[]; Grid_ParseLotSequence("10-20",gaps);
   T1710Eq("grid price unit first",Grid_ChainDistancePrice(1,gaps,.0001),.001);
   T1710Eq("grid price unit repeat",Grid_ChainDistancePrice(9,gaps,.0001),.002);
   T1710Check("default migration mode legacy",UnitSystemMode_==unit_LEGACY_COMPAT);
   Config_Init(); why="";
   T1710Check("bind synthetic XAU3",Config_BindUnitProfile(true,.001,3,.01,why));
   T1710Eq("bound legacy TP200",Cfg.TPPrice,2.0);
   T1710Eq("bound legacy DCA input unit",Cfg.DcaInputUnitPrice,.1);
   T1710Eq("bound legacy slippage3",Cfg.SlippagePrice,.03);
   T1710Check("bound legacy point scale",Cfg.PointScale==10);
   T1710Check("mode legacy name",Unit_ModeName(unit_LEGACY_COMPAT)=="LEGACY_COMPAT");
   T1710Check("mode unified name",Unit_ModeName(unit_PIP_UNIFIED)=="PIP_UNIFIED");

   Print("T17.10 unit tests: ",g_t1710_pass," passed, ",g_t1710_fail," failed");
   if(g_t1710_fail==0) Print("ALL GREEN");
}
