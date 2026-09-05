#property script_show_inputs
#include <BlackDragon/Recovery/RecoveryOpenBarPolicy.mqh>
int g_pass=0,g_fail=0;
void Check(const string name,const bool ok){if(ok)g_pass++;else{g_fail++;Print("FAIL: ",name);}}
void OnStart()
{
   Check("OFF ignores missing evidence",Recovery_OpenBarAllowsPure(false,false,false,false));
   Check("OFF ignores existing RH",Recovery_OpenBarAllowsPure(false,true,true,true));
   Check("ON missing bar waits",!Recovery_OpenBarAllowsPure(true,false,true,false));
   Check("ON missing history waits",!Recovery_OpenBarAllowsPure(true,true,false,false));
   Check("ON occupied bar waits",!Recovery_OpenBarAllowsPure(true,true,true,true));
   Check("ON free bar allows",Recovery_OpenBarAllowsPure(true,true,true,false));
   Check("exact owned opening",Recovery_OpenBarEntryMatchesPure(true,true,true,true,6001000,6000000));
   Check("wrong symbol",!Recovery_OpenBarEntryMatchesPure(false,true,true,true,6001000,6000000));
   Check("wrong owner",!Recovery_OpenBarEntryMatchesPure(true,false,true,true,6001000,6000000));
   Check("opposite direction",!Recovery_OpenBarEntryMatchesPure(true,true,false,true,6001000,6000000));
   Check("closing entry",!Recovery_OpenBarEntryMatchesPure(true,true,true,false,6001000,6000000));
   Check("prior bar",!Recovery_OpenBarEntryMatchesPure(true,true,true,true,5940000,6000000));
   Check("exact boundary",Recovery_OpenBarEntryMatchesPure(true,true,true,true,6000000,6000000));
   Check("after boundary",Recovery_OpenBarEntryMatchesPure(true,true,true,true,6000001,6000000));
   Check("zero bar",!Recovery_OpenBarEntryMatchesPure(true,true,true,true,6001000,0));
   Check("negative bar",!Recovery_OpenBarEntryMatchesPure(true,true,true,true,6001000,-1));
   bool coreOpen=Recovery_OpenBarEntryMatchesPure(true,false,true,true,6001000,6000000);
   bool rhOpen=Recovery_OpenBarEntryMatchesPure(true,true,true,true,6001000,6000000);
   bool nextBar=Recovery_OpenBarEntryMatchesPure(true,true,true,true,6001000,6060000);
   bool opposite=Recovery_OpenBarEntryMatchesPure(true,true,false,true,6001000,6000000);
   Check("first RH after Core",Recovery_OpenBarAllowsPure(true,true,true,coreOpen));
   Check("BE closed RH still counted",!Recovery_OpenBarAllowsPure(true,true,true,rhOpen));
   Check("SL closed RH still counted",!Recovery_OpenBarAllowsPure(true,true,true,rhOpen));
   Check("generation reset keeps historical slot",!Recovery_OpenBarAllowsPure(true,true,true,rhOpen));
   Check("next bar allows",Recovery_OpenBarAllowsPure(true,true,true,nextBar));
   Check("opposite direction independent",Recovery_OpenBarAllowsPure(true,true,true,opposite));
   Check("partial fill occupies bar",!Recovery_OpenBarAllowsPure(true,true,true,rhOpen));
   Check("rejected unfilled request leaves bar free",Recovery_OpenBarAllowsPure(true,true,true,false));
   Print("T17.20 RH one-bar tests: ",g_pass," passed, ",g_fail," failed");
   if(g_fail==0)Print("ALL GREEN");else Print("TESTS FAILED");
}
