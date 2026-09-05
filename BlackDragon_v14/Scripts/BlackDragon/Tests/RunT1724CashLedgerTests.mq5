#property strict
#property script_show_inputs
int t1724_passed=0,t1724_failed=0;
void T1724Check(const string name,const bool ok)
{
   if(ok) t1724_passed++;
   else { t1724_failed++; Print("FAIL: ",name); }
}
#include <BlackDragon/Pyramid/PyramidProtectionPolicy.mqh>
#include "t1724_cash_fixture.mqh"
void OnStart()
{
   T1724RunCashCases();
   Print("T17.24 cash integration: ",t1724_passed," passed, ",t1724_failed," failed");
   if(t1724_failed==0) Print("ALL GREEN");
}
