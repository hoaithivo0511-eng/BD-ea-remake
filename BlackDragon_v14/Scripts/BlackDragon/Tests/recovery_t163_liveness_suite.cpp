// T16.3 ARCS — deferred-lock and max-generation liveness regression.
#include <cstdio>
using namespace std;
static int pass_count=0, fail_count=0;
static void Check(const char*n,bool ok){if(ok)++pass_count;else{++fail_count;printf("FAIL: %s\n",n);}}

enum ViewState { HEDGE_LOCK_PENDING=0, HEDGE_LOCKED=1, REHEDGE_PENDING=2, PAUSE_SOFT=3 };

static bool DeferredYield(bool consumed,bool deterministic,bool pending,bool reconcile){
 return consumed&&deterministic&&!pending&&!reconcile;
}
static bool MaxedNoHedge(int generation,int maxGen,long core,long hedge,bool terminalPhase){
 return terminalPhase&&maxGen>=1&&generation>=maxGen&&core>0&&hedge<=0;
}
static ViewState Scheduling(ViewState base,bool deferred,bool maxed){
 if(deferred)return REHEDGE_PENDING;
 if(maxed)return HEDGE_LOCKED;
 return base;
}
static bool GenerationCanStart(int generation,int maxGen){
 return generation>=0&&maxGen>=1&&generation<maxGen;
}
static bool DcaStable(ViewState s){return s==HEDGE_LOCKED||s==REHEDGE_PENDING;}
static bool OverlapStable(ViewState s){return s==HEDGE_LOCKED;}

int main(){
 // Exact owner starvation #1: deterministic local SL wait is NOT an unresolved
 // mutation. It may yield Core DCA, while broker pending/ambiguity must not.
 Check("deterministic lock wait yields",DeferredYield(true,true,false,false));
 Check("normal consumed mutation does not yield",!DeferredYield(true,false,false,false));
 Check("pending modify does not yield",!DeferredYield(true,true,true,false));
 Check("ambiguous modify does not yield",!DeferredYield(true,true,false,true));
 Check("non-consumed path does not synthesize yield",!DeferredYield(false,true,false,false));
 Check("deferred view is REHEDGE_PENDING",Scheduling(HEDGE_LOCK_PENDING,true,false)==REHEDGE_PENDING);
 Check("deferred view lets DCA continue",DcaStable(Scheduling(HEDGE_LOCK_PENDING,true,false)));
 Check("deferred view still blocks Overlap",!OverlapStable(Scheduling(HEDGE_LOCK_PENDING,true,false)));

 // Exact owner starvation #2: G==Max, Hedge=0, Core>0 is terminal for Recovery
 // generations but NOT terminal for Core management.
 Check("G30 Max30 Core4 Hedge0 is maxed-no-hedge",MaxedNoHedge(30,30,4,0,true));
 Check("G31 forbidden at max",!GenerationCanStart(30,30));
 Check("G29 still may start G30",GenerationCanStart(29,30));
 Check("maxed view is HEDGE_LOCKED scheduling",Scheduling(PAUSE_SOFT,false,true)==HEDGE_LOCKED);
 Check("maxed view lets DCA continue",DcaStable(Scheduling(PAUSE_SOFT,false,true)));
 Check("maxed view lets stable Overlap continue",OverlapStable(Scheduling(PAUSE_SOFT,false,true)));
 Check("no Core means no maxed-no-hedge hold",!MaxedNoHedge(30,30,0,0,true));
 Check("remaining Hedge means not maxed-no-hedge",!MaxedNoHedge(30,30,4,1,true));
 Check("pre-Max does not become terminal",!MaxedNoHedge(29,30,4,0,true));
 Check("non-terminal phase does not become terminal",!MaxedNoHedge(30,30,4,0,false));

 printf("Recovery T16.3 liveness suite: %d passed, %d failed\n",pass_count,fail_count);
 if(fail_count==0) printf("ALL GREEN — T16.3 deferred-lock/max-generation liveness passed.\n");
 return fail_count==0?0:1;
}
