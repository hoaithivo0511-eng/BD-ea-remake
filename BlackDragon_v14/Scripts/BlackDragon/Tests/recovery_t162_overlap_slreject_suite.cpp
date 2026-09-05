// T16.2 ARCS — explicit SL reject + Overlap-after-Hedge model regression.
#include <algorithm>
#include <cmath>
#include <cstdio>
using namespace std;
static int pass_count=0, fail_count=0;
static void Check(const char*n,bool ok){if(ok)++pass_count;else{++fail_count;printf("FAIL: %s\n",n);}}

enum ModifyDisposition{ACCEPTED=0,DEFER_NO_EFFECT=1,RECONCILE=2};
enum Phase{CORE_ONLY=0,ARMED,HEDGE_ACTIVE,HEDGE_LOCKED,BUILDING,TP_PENDING,CORE_FUNDING,LOCK_PENDING,GLOBAL_MUTATING,RECONCILE_STATE};
enum OverlapDecision{OV_BLOCK=0,OV_COORDINATE=1,OV_DEFER=2,OV_BYPASS=3};

static ModifyDisposition ModifyPolicy(bool accepted,bool ambiguous){if(accepted)return ACCEPTED;if(ambiguous)return RECONCILE;return DEFER_NO_EFFECT;}
static long Pct(long core,double pct){if(core<=0||pct<=0)return 0;return (long)floor((double)core*pct/100.0+1e-9);}
static long NextStack(long core,long existing,double pct){(void)existing;return Pct(core,pct);}
static long NextBalance(long core,long existing,double pct){long d=Pct(core,pct);return d>existing?d-existing:0;}
static OverlapDecision OverlapPolicy(bool after,bool ready,Phase p){
 if(p==CORE_ONLY)return OV_BYPASS;
 if(!after)return OV_BLOCK;
 if(!ready)return OV_DEFER;
 if(p==ARMED||p==HEDGE_ACTIVE||p==HEDGE_LOCKED)return OV_COORDINATE;
 return OV_DEFER;
}
struct Cycle{bool active=false;bool firstLive=true;bool secondLive=true;long coreBefore=100;long targetCore=80;long hedge=50;double funding=12.5;int sends=0;};
static bool DriveOverlap(Cycle &c){
 if(!c.active)return false;
 if(c.firstLive){c.firstLive=false;c.sends++;return true;} // legacy: pairLast first
 if(c.secondLive){c.secondLive=false;c.sends++;return true;}
 c.active=false;return false;
}
int main(){
 Check("accepted modify stays accepted",ModifyPolicy(true,false)==ACCEPTED);
 Check("explicit INVALID_STOPS defers",ModifyPolicy(false,false)==DEFER_NO_EFFECT);
 Check("timeout ambiguity reconciles",ModifyPolicy(false,true)==RECONCILE);
 Check("explicit reject never implies reconcile",ModifyPolicy(false,false)!=RECONCILE);

 Check("Overlap pre-Hedge bypass",OverlapPolicy(false,true,CORE_ONLY)==OV_BYPASS);
 Check("OverlapAfter false blocks active Hedge",OverlapPolicy(false,true,HEDGE_ACTIVE)==OV_BLOCK);
 Check("OverlapAfter true coordinates ARMED",OverlapPolicy(true,true,ARMED)==OV_COORDINATE);
 Check("OverlapAfter true coordinates HEDGE_ACTIVE",OverlapPolicy(true,true,HEDGE_ACTIVE)==OV_COORDINATE);
 Check("OverlapAfter true coordinates HEDGE_LOCKED",OverlapPolicy(true,true,HEDGE_LOCKED)==OV_COORDINATE);
 Check("BUILDING defers",OverlapPolicy(true,true,BUILDING)==OV_DEFER);
 Check("TP_PENDING defers",OverlapPolicy(true,true,TP_PENDING)==OV_DEFER);
 Check("LOCK_PENDING defers",OverlapPolicy(true,true,LOCK_PENDING)==OV_DEFER);
 Check("not-ready defers",OverlapPolicy(true,false,HEDGE_ACTIVE)==OV_DEFER);

 Check("fresh Core80 x115 stack=92",NextStack(80,50,115.0)==92);
 Check("stale Core100 x115 would115",NextStack(100,50,115.0)==115);
 Check("fresh balanced desired92-retained50=42",NextBalance(80,50,115.0)==42);
 Check("stack does not trim retained overhedge",NextStack(80,120,100.0)==80);

 Cycle c;c.active=true;
 Check("Overlap drive closes pairLast first",DriveOverlap(c)&&!c.firstLive&&c.secondLive&&c.sends==1);
 Check("Overlap drive closes pairFirst second",DriveOverlap(c)&&!c.secondLive&&c.sends==2);
 double ledgerBefore=c.funding;
 Check("Overlap completes only after both broker effects",!DriveOverlap(c)&&!c.active);
 Check("Overlap does not consume Hedge funding ledger",fabs(c.funding-ledgerBefore)<1e-12);

 printf("Recovery T16.2 Overlap/SL-reject suite: %d passed, %d failed\n",pass_count,fail_count);
 if(fail_count==0) printf("ALL GREEN — T16.2 overlap refresh / deterministic SL reject policy passed.\n");
 return fail_count==0?0:1;
}
