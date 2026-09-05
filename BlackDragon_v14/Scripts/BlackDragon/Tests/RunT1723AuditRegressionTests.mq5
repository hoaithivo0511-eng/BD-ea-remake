#property strict
// T17.23 regressions promoted from the independent PR #28 deep audit.
#include <BlackDragon/Pyramid/PyramidProtectionPolicy.mqh>
int passed=0,failed=0;
void T1723_Check(const string name,const bool ok)
{ if(ok) passed++; else { failed++; Print("FAIL ",name); } }
#include "t1723_audit_regression_cases.mqh"
void OnStart()
{
   T1723_RunCases();
   Print("T17.23 audit regressions: ",passed," passed, ",failed," failed");
   if(failed==0) Print("ALL GREEN"); else Print("TESTS FAILED");
}
