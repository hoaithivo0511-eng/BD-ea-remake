#property strict
// digits-tested: 3, 5
#include <BlackDragon/Pyramid/PyramidProtectionPolicy.mqh>
int passed=0,failed=0;
void T1722_Check(const string name,const bool ok)
{ if(ok) passed++; else { failed++; Print("FAIL ",name); } }
#include "t1722_protection_cases.mqh"
void OnStart()
{
   T1722_RunCases();
   Print("T17.22 PY protection: ",passed," passed, ",failed," failed");
   if(failed==0) Print("ALL GREEN"); else Print("TESTS FAILED");
}
