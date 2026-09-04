#property strict
#property script_show_inputs
// digits-tested: unitless order identities.
#include <BlackDragon/OrderCommentCodec.mqh>
int passed=0,failed=0;
void T1721Check(const string name,const bool ok)
{
   if(ok) passed++;
   else { failed++; Print("FAIL ",name); }
}
#include "t1721_comment_cases.mqh"
void OnStart()
{
   T1721CodecCases();
   Print("T17.21 order comment tests: ",passed," passed, ",failed," failed");
   if(failed==0) Print("ALL GREEN");
   TerminalClose(failed==0?0:1);
}
