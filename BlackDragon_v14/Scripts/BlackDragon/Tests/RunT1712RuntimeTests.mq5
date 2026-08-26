#property script_show_inputs
#include <BlackDragon/Recovery/RecoveryT1712EconomicPolicy.mqh>
#include <BlackDragon/MoneyGuard.mqh>

int g_pass=0,g_fail=0;
void T(bool v,string n){ if(v) g_pass++; else { g_fail++; Print("FAIL: ",n); } }

void OnStart()
{
   T(!Recovery_T1712ExitFundedPure(true,true,106.40,-448.49,0.0,100.0,5.0),
     "SELL negative whole-cycle virtual TP blocks");
   T(!Recovery_T1712ExitFundedPure(true,true,215.29,-425.59,0.0,100.0,5.0),
     "BUY negative whole-cycle virtual TP blocks");
   T(Recovery_T1712ExitFundedPure(true,true,215.29,-80.0,0.0,100.0,5.0),
     "funded Recovery exit passes");
   T(Recovery_T1712ExitFundedPure(false,false,-999,-999,-999,999,DBL_MAX),
     "Core-only parity bypasses T17.12 economic gate");
   T(!Recovery_T1712ExitFundedPure(true,false,500,0,0,100,5),
     "invalid snapshot fails closed");
   T(!Recovery_T1712ExitFundedPure(true,true,500,0,0,100,DBL_MAX),
     "invalid reserve fails closed");
   T(!Recovery_T1712ExitFundedPure(true,true,150,-20,-40,100,5),
     "Pyramid campaign debt included");
   T(Recovery_T1712ExitFundedPure(true,true,170,-20,-40,100,5),
     "Pyramid campaign debt repaid");

   double tp=0.0;
   T(Recovery_T1712ProjectedTpPure(true,1.1000,1.1010,40,-20,0,100,5,100000,tp) && tp>=1.1010,
     "BUY under hedge projects outward");
   T(Recovery_T1712ProjectedTpPure(false,1.1000,1.0990,40,-20,0,100,5,-100000,tp) && tp<=1.0990,
     "SELL under hedge projects outward");
   T(!Recovery_T1712ProjectedTpPure(true,1.1000,1.1010,40,-40,0,100,5,0,tp),
     "BUY full hedge no finite target");
   T(!Recovery_T1712ProjectedTpPure(false,1.1000,1.0990,40,-40,0,100,5,0,tp),
     "SELL full hedge no finite target");
   T(!Recovery_T1712ProjectedTpPure(true,1.1000,1.1010,40,-60,0,100,5,-100000,tp),
     "BUY over hedge no unsafe target");
   T(!Recovery_T1712ProjectedTpPure(false,1.1000,1.0990,40,-60,0,100,5,100000,tp),
     "SELL over hedge no unsafe target");
   T(!Recovery_T1712ProjectedTpPure(true,1.1000,1.1010,40,-20,0,100,DBL_MAX,100000,tp),
     "REAL TP invalid economics fails closed");

   T(MathAbs(Recovery_T1712NominalTargetCashPure(1.1010,1.1000,1.0,0.0001,10.0)-100.0)<1e-9,
     "nominal TP cash conversion");
   T(MathAbs(Recovery_T1712CashSlopePerPricePure(true,1.0,0.4,0.0001,10.0)-60000.0)<1e-6,
     "BUY under hedge slope");
   T(MathAbs(Recovery_T1712CashSlopePerPricePure(false,1.0,0.4,0.0001,10.0)+60000.0)<1e-6,
     "SELL under hedge slope");

   T(MG_MoneyTpHit(100.12,100.0),"MoneyTP raw arm threshold unchanged");
   T(MathAbs(MG_AccountTpCloseReserveLegCashPure(0.0002,0.0001,1.0,0.0001,10.0)-50.0)<1e-9,
     "account TP close-leg reserve");
   T(MG_AccountTpCloseReserveLegCashPure(0.0002,0.0001,1.0,0.0,10.0)==DBL_MAX,
     "account TP invalid metadata fails closed");

   Print("T17.12 runtime tests: ",g_pass," passed, ",g_fail," failed");
   if(g_fail==0) Print("ALL GREEN");
}
