#property strict
#include <BlackDragon/Recovery/RecoveryT1717StopLivenessPolicy.mqh>

int g_pass=0,g_fail=0;
void T(const bool ok,const string name)
{
   if(ok) g_pass++;
   else { g_fail++; Print("FAIL: ",name); }
}

void OnStart()
{
   eRecoveryT1717CoordinatorOwner none =
      Recovery_T1717CoordinatorOwnerPure(false,false);
   eRecoveryT1717CoordinatorOwner side =
      Recovery_T1717CoordinatorOwnerPure(false,true);
   eRecoveryT1717CoordinatorOwner account =
      Recovery_T1717CoordinatorOwnerPure(true,true);
   T(none==RECOVERY_T1717_OWNER_NONE,"no coordinator owner");
   T(side==RECOVERY_T1717_OWNER_SIDE,"side cycle owner");
   T(account==RECOVERY_T1717_OWNER_ACCOUNT,"account owner preempts side");
   T(Recovery_T1717ExpectedArcsSlBypassPure(true,none,true),
     "exact ARCS SL bypasses ordinary external classifier");
   T(Recovery_T1717ExpectedArcsSlBypassPure(true,side,true),
     "exact ARCS SL remains internal during Overlap side cycle");
   T(!Recovery_T1717ExpectedArcsSlBypassPure(true,account,true),
     "account-wide close retains settlement authority");
   T(!Recovery_T1717ExpectedArcsSlBypassPure(true,side,false),
     "missing exact SL proof remains fail closed");
   T(!Recovery_T1717ExpectedArcsSlBypassPure(false,side,true),
     "non ARCS mode does not use T17.17 bypass");

   T(Recovery_T1717VerifiedAccountFlatResetPure(true,0,false,false),
     "verified quiet account flat authorizes reset");
   T(!Recovery_T1717VerifiedAccountFlatResetPure(false,0,false,false),
     "incidental flat without guard epoch cannot reset");
   T(!Recovery_T1717VerifiedAccountFlatResetPure(true,1,false,false),
     "live account position blocks reset");
   T(!Recovery_T1717VerifiedAccountFlatResetPure(true,0,true,false),
     "execution journal blocks reset");
   T(!Recovery_T1717VerifiedAccountFlatResetPure(true,0,false,true),
     "Recovery coordinator blocks reset");
   T(Recovery_T1717RelatchAccountGuardPure(true,false),
     "reset persistence failure relatches account guard");
   T(!Recovery_T1717RelatchAccountGuardPure(true,true),
     "successful reset leaves guard complete");
   T(!Recovery_T1717RelatchAccountGuardPure(false,false),
     "non completion does not invent account guard");

   Print("T17.17 native stop/liveness: ",g_pass,
         " passed, ",g_fail," failed");
   if(g_fail==0) Print("ALL GREEN");
   if(g_fail>0) ExpertRemove();
}

