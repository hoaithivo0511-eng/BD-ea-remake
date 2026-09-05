// Adaptive Recovery T14 — execution identity / protective-SL model suite.
#include <cmath>
#include <cstdio>
using namespace std;

static int g_pass=0,g_fail=0;
static void Check(const char*name,bool ok){if(ok){g_pass++;return;}g_fail++;printf("FAIL: %s\n",name);}

enum Rc { DONE=10009, DONE_PARTIAL=10010, PLACED=10008, TIMEOUT=10012, CONNECTION=10031 };

static bool OpenComplete(unsigned rc,bool req,bool owner,bool deal,bool order,bool orderLive,
                         double observed,double target,double step){
  if(rc!=DONE&&rc!=DONE_PARTIAL) return false;
  if(!req||!owner||!deal||!order||orderLive) return false;
  if(observed<=0||target<=0) return false;
  double eps=step>0?step*.5:1e-9;
  return observed+eps>=target;
}
static bool StrictAmbiguous(unsigned rc){return rc==TIMEOUT||rc==CONNECTION;}
static bool ProtectiveSl(bool owner,bool position,long reason,double programmed,double target,
                         double fill,double slTol,double fillTol,bool modifyProof){
  if(!owner||!position||reason!=4||target<=0||fill<=0||slTol<0||fillTol<0) return false;
  bool programmedMatch=programmed>0&&fabs(programmed-target)<=slTol+1e-12;
  if(!programmedMatch&&!modifyProof) return false;
  return fabs(fill-target)<=fillTol+1e-12;
}
static bool GlobalRelease(bool flat,bool terminal,bool ambiguous){return flat&&terminal&&!ambiguous;}

int main(){
  Check("same-count replacement identity completes",OpenComplete(DONE,true,true,true,true,false,.08,.08,.01));
  Check("owner mismatch",!OpenComplete(DONE,true,false,true,true,false,.08,.08,.01));
  Check("request mismatch",!OpenComplete(DONE,false,true,true,true,false,.08,.08,.01));
  Check("deal mismatch",!OpenComplete(DONE,true,true,false,true,false,.08,.08,.01));
  Check("server order still live",!OpenComplete(DONE,true,true,true,true,true,.08,.08,.01));
  Check("DONE",OpenComplete(DONE,true,true,true,true,false,.08,.08,.01));
  Check("DONE_PARTIAL short pending",!OpenComplete(DONE_PARTIAL,true,true,true,true,false,.03,.08,.01));
  Check("DONE_PARTIAL cumulative target",OpenComplete(DONE_PARTIAL,true,true,true,true,false,.08,.08,.01));
  Check("PLACED pending",!OpenComplete(PLACED,true,true,true,true,false,0,.08,.01));
  Check("TIMEOUT strict ambiguous",StrictAmbiguous(TIMEOUT));
  Check("CONNECTION strict ambiguous",StrictAmbiguous(CONNECTION));
  Check("historical deal stays terminal after position closed",OpenComplete(DONE,true,true,true,true,false,.08,.08,.01));
  Check("lock pending identity",ProtectiveSl(true,true,4,4480.386,4480.386,4480.479,.02,.50,true));
  Check("lock locked identity",ProtectiveSl(true,true,4,4480.386,4480.386,4480.479,.02,.50,true));
  Check("state advanced identity",ProtectiveSl(true,true,4,4480.386,4480.386,4480.479,.02,.50,true));
  Check("random SL external",!ProtectiveSl(true,true,4,4470,4480.386,4470.01,.02,.50,false));
  Check("manual wrong owner external",!ProtectiveSl(false,true,4,4480.386,4480.386,4480.479,.02,.50,true));
  Check("global flat terminal proof releases",GlobalRelease(true,true,false));
  Check("global flat ambiguous remains blocked",!GlobalRelease(true,false,true));
  printf("Recovery T14 identity model: %d passed, %d failed\n",g_pass,g_fail);
  return g_fail?1:0;
}
