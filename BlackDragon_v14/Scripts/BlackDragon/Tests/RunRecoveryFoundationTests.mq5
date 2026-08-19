//+------------------------------------------------------------------+
//| RunRecoveryFoundationTests.mq5 — Adaptive Recovery Hedge T1      |
//| Pure foundation tests only. No trade requests are sent.          |
//+------------------------------------------------------------------+
#property script_show_inputs
#include <BlackDragon/Recovery/RecoveryTypes.mqh>

int g_pass = 0;
int g_fail = 0;

void Check(const string name, const bool cond)
{
   if(cond) { g_pass++; return; }
   g_fail++;
   Print("FAIL: ", name);
}

void CheckEq(const string name, const double got, const double want, const double eps=1e-9)
{
   Check(name, MathAbs(got-want) <= eps);
}

void OnStart()
{
   Check("DCA flat -> 0", Recovery_DcaCountFromCoreCount(0)==0);
   Check("DCA initial Core -> 0", Recovery_DcaCountFromCoreCount(1)==0);
   Check("DCA count2 -> 1", Recovery_DcaCountFromCoreCount(2)==1);
   Check("DCA count6 -> 5", Recovery_DcaCountFromCoreCount(6)==5);
   Check("N5 before boundary", !Recovery_DcaThresholdReached(5,5));
   Check("N5 at boundary", Recovery_DcaThresholdReached(6,5));
   Check("N0 flat false", !Recovery_DcaThresholdReached(0,0));
   Check("N0 initial Core true", Recovery_DcaThresholdReached(1,0));
   Check("negative threshold false", !Recovery_DcaThresholdReached(10,-1));

   Check("0.245/.01 floors 24", Recovery_VolumeToUnitsFloor(0.245,0.01)==24);
   Check(".30/.10 exact 3", Recovery_VolumeToUnitsFloor(0.30,0.10)==3);
   Check("12.37/.01 = 1237", Recovery_VolumeToUnitsFloor(12.37,0.01)==1237);
   CheckEq("24 units=.24", Recovery_UnitsToVolume(24,0.01),0.24,1e-12);

   CheckEq("XAU 2d pip .10", Recovery_PipSizePure(true,0.01,2),0.10,1e-12);
   CheckEq("XAU 3d pip .10", Recovery_PipSizePure(true,0.001,3),0.10,1e-12);
   CheckEq("XAU 50 pip=5 2d", Recovery_PipsToPricePure(50,true,0.01,2),5.0,1e-12);
   CheckEq("XAU 50 pip=5 3d", Recovery_PipsToPricePure(50,true,0.001,3),5.0,1e-12);
   Check("XAU 50 pip=500 ticks 2d", Recovery_PipsToTicksPure(50,true,0.01,2,0.01)==500);
   Check("XAU 50 pip=5000 ticks 3d", Recovery_PipsToTicksPure(50,true,0.001,3,0.001)==5000);
   CheckEq("FX 5d pip=.0001", Recovery_PipSizePure(false,0.00001,5),0.0001,1e-12);

   string why="";
   Check("OFF keeps legacy permissive init",
         Recovery_ValidateFoundation(recovery_OFF,1111,1111,-5,ACCOUNT_MARGIN_MODE_RETAIL_NETTING,why));
   Check("SHADOW allowed on netting",
         Recovery_ValidateFoundation(recovery_SHADOW,1111,20260807,5,ACCOUNT_MARGIN_MODE_RETAIL_NETTING,why));
   Check("SHADOW rejects magic collision",
         !Recovery_ValidateFoundation(recovery_SHADOW,1111,1111,5,ACCOUNT_MARGIN_MODE_RETAIL_NETTING,why));
   Check("SHADOW rejects zero recovery magic",
         !Recovery_ValidateFoundation(recovery_SHADOW,1111,0,5,ACCOUNT_MARGIN_MODE_RETAIL_NETTING,why));
   Check("ACTIVE rejects netting",
         !Recovery_ValidateFoundation(recovery_ACTIVE,1111,20260807,5,ACCOUNT_MARGIN_MODE_RETAIL_NETTING,why));
   Check("ACTIVE accepts hedging",
         Recovery_ValidateFoundation(recovery_ACTIVE,1111,20260807,5,ACCOUNT_MARGIN_MODE_RETAIL_HEDGING,why));

   PrintFormat("Recovery T1 foundation tests: %d passed, %d failed",g_pass,g_fail);
   if(g_fail==0) Print("ALL GREEN — T1 pure foundation behavior passed.");
}
