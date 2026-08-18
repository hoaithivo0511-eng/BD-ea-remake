// Adaptive Recovery Hedge T1 — standalone offline pure-function suite.
// Mirrors RecoveryMath.mqh + Recovery_ValidateFoundation semantics.
#include <cmath>
#include <cstdio>
#include <string>
using namespace std;

static int pass_count = 0, fail_count = 0;
static void Check(const char *name, bool ok){ if(ok){pass_count++;return;} fail_count++; printf("FAIL: %s\n", name); }
static void CheckEq(const char *name, double got, double want, double eps=1e-9){ Check(name, fabs(got-want)<=eps); }

static const int BD_POINTS_PER_PIP = 10;
static const long ACCOUNT_MARGIN_MODE_RETAIL_NETTING = 0;
static const long ACCOUNT_MARGIN_MODE_RETAIL_HEDGING = 2;

enum eRecoveryMode { recovery_OFF=0, recovery_SHADOW=1, recovery_ACTIVE=2 };

int Recovery_DcaCountFromCoreCount(const int coreOpenCount)
{ return coreOpenCount <= 1 ? 0 : coreOpenCount - 1; }

bool Recovery_DcaThresholdReached(const int coreOpenCount, const int startAfterDca)
{
   if(coreOpenCount <= 0 || startAfterDca < 0) return false;
   return Recovery_DcaCountFromCoreCount(coreOpenCount) >= startAfterDca;
}

long Recovery_VolumeToUnitsFloor(const double volume, const double volumeStep)
{
   if(volume <= 0.0 || volumeStep <= 0.0) return 0;
   return (long)floor(volume / volumeStep + 1e-9);
}

double Recovery_UnitsToVolume(const long units, const double volumeStep)
{
   if(units <= 0 || volumeStep <= 0.0) return 0.0;
   return round((double)units * volumeStep * 1e8) / 1e8;
}

double Recovery_PipSizePure(const bool isGold, const double point, const int digits)
{
   if(point <= 0.0) return 0.0;
   if(isGold) return 0.01 * BD_POINTS_PER_PIP;
   return (digits == 3 || digits == 5) ? point * 10.0 : point;
}

double Recovery_PipsToPricePure(const double pips, const bool isGold, const double point, const int digits)
{ return pips * Recovery_PipSizePure(isGold, point, digits); }

long Recovery_PriceToTicksPure(const double price, const double tickSize)
{ return tickSize <= 0.0 ? 0 : (long)llround(price / tickSize); }

long Recovery_PipsToTicksPure(const double pips, const bool isGold, const double point,
                              const int digits, const double tickSize)
{
   if(tickSize <= 0.0) return 0;
   return (long)llround(Recovery_PipsToPricePure(pips,isGold,point,digits)/tickSize);
}

bool Recovery_ModeValid(const eRecoveryMode mode)
{ return mode==recovery_OFF || mode==recovery_SHADOW || mode==recovery_ACTIVE; }

bool Recovery_ValidateFoundation(const eRecoveryMode mode, const long coreMagic,
                                 const long recoveryMagic, const int startAfterDca,
                                 const long marginMode, string &why)
{
   why.clear();
   if(!Recovery_ModeValid(mode)){ why="RecoveryMode_ invalid"; return false; }
   if(mode==recovery_OFF) return true;
   if(recoveryMagic<=0){ why="RecoveryMagic_ must be > 0 when Recovery is enabled"; return false; }
   if(recoveryMagic==coreMagic){ why="RecoveryMagic_ must differ from Core Magic"; return false; }
   if(startAfterDca<0){ why="RecoveryStartAfterDca_ must be >= 0"; return false; }
   if(mode==recovery_ACTIVE && marginMode!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING){
      why="Recovery ACTIVE requires ACCOUNT_MARGIN_MODE_RETAIL_HEDGING"; return false;
   }
   return true;
}

int main()
{
   Check("DCA flat -> 0", Recovery_DcaCountFromCoreCount(0)==0);
   Check("DCA initial core -> 0", Recovery_DcaCountFromCoreCount(1)==0);
   Check("DCA core count 2 -> 1", Recovery_DcaCountFromCoreCount(2)==1);
   Check("DCA core count 6 -> 5", Recovery_DcaCountFromCoreCount(6)==5);
   Check("threshold N=5 before boundary", !Recovery_DcaThresholdReached(5,5));
   Check("threshold N=5 at boundary", Recovery_DcaThresholdReached(6,5));
   Check("threshold N=0 flat false", !Recovery_DcaThresholdReached(0,0));
   Check("threshold N=0 initial core true", Recovery_DcaThresholdReached(1,0));
   Check("negative threshold never arms", !Recovery_DcaThresholdReached(10,-1));

   Check("units 0.245 step .01 -> 24", Recovery_VolumeToUnitsFloor(0.245,0.01)==24);
   Check("units exact .30/.10 -> 3", Recovery_VolumeToUnitsFloor(0.30,0.10)==3);
   Check("units 12.37/.01 -> 1237", Recovery_VolumeToUnitsFloor(12.37,0.01)==1237);
   Check("units invalid step -> 0", Recovery_VolumeToUnitsFloor(1.0,0)==0);
   CheckEq("24 units -> .24", Recovery_UnitsToVolume(24,0.01),0.24,1e-12);
   CheckEq("1237 units -> 12.37", Recovery_UnitsToVolume(1237,0.01),12.37,1e-12);

   CheckEq("XAU 2d pip=.10", Recovery_PipSizePure(true,0.01,2),0.10,1e-12);
   CheckEq("XAU 3d pip=.10", Recovery_PipSizePure(true,0.001,3),0.10,1e-12);
   CheckEq("XAU 50 pip=5.00 2d", Recovery_PipsToPricePure(50,true,0.01,2),5.0,1e-12);
   CheckEq("XAU 50 pip=5.00 3d", Recovery_PipsToPricePure(50,true,0.001,3),5.0,1e-12);
   Check("XAU 50 pip -> 500 ticks @.01", Recovery_PipsToTicksPure(50,true,0.01,2,0.01)==500);
   Check("XAU 50 pip -> 5000 ticks @.001", Recovery_PipsToTicksPure(50,true,0.001,3,0.001)==5000);
   CheckEq("FX 5d pip=.0001", Recovery_PipSizePure(false,0.00001,5),0.0001,1e-12);
   Check("price ticks round", Recovery_PriceToTicksPure(4195.00,0.01)==419500);

   string why;
   Check("OFF permissive on netting/collision", Recovery_ValidateFoundation(recovery_OFF,1111,1111,-5,ACCOUNT_MARGIN_MODE_RETAIL_NETTING,why));
   Check("SHADOW valid on netting", Recovery_ValidateFoundation(recovery_SHADOW,1111,20260807,5,ACCOUNT_MARGIN_MODE_RETAIL_NETTING,why));
   Check("SHADOW collision rejected", !Recovery_ValidateFoundation(recovery_SHADOW,1111,1111,5,ACCOUNT_MARGIN_MODE_RETAIL_NETTING,why));
   Check("SHADOW zero magic rejected", !Recovery_ValidateFoundation(recovery_SHADOW,1111,0,5,ACCOUNT_MARGIN_MODE_RETAIL_NETTING,why));
   Check("SHADOW negative DCA rejected", !Recovery_ValidateFoundation(recovery_SHADOW,1111,20260807,-1,ACCOUNT_MARGIN_MODE_RETAIL_NETTING,why));
   Check("ACTIVE netting rejected", !Recovery_ValidateFoundation(recovery_ACTIVE,1111,20260807,5,ACCOUNT_MARGIN_MODE_RETAIL_NETTING,why));
   Check("ACTIVE hedging accepted", Recovery_ValidateFoundation(recovery_ACTIVE,1111,20260807,5,ACCOUNT_MARGIN_MODE_RETAIL_HEDGING,why));

   printf("Recovery T1 foundation: %d passed, %d failed\n", pass_count, fail_count);
   return fail_count==0 ? 0 : 1;
}
