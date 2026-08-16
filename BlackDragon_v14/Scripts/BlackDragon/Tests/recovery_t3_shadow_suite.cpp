// Adaptive Recovery Hedge T3 — standalone pure FSM/SHADOW model tests.
#include <cmath>
#include <cstdio>
using namespace std;

static int pass_count=0, fail_count=0;
static void Check(const char* n,bool ok){ if(ok){pass_count++;return;} fail_count++; printf("FAIL: %s\n",n); }
static void CheckEq(const char* n,double a,double b,double e=1e-9){ Check(n,fabs(a-b)<=e); }

enum Dir{ BUY_CORE=0, SELL_CORE=1 };
enum State{ CORE_ONLY=0, ARMED, HEDGE_BUILDING, HEDGE_ACTIVE, HEDGE_TP_PENDING,
            CORE_CLOSE_PENDING, HEDGE_LOCK_PENDING, HEDGE_LOCKED, REHEDGE_PENDING,
            PAUSE_SOFT, PAUSE_HARD, RECONCILE_REQUIRED, GLOBAL_STOP, COMPLETED };

static int DcaCount(int coreCount){ return coreCount<=1?0:coreCount-1; }
static bool Threshold(int coreCount,int n){ return coreCount>0 && n>=0 && DcaCount(coreCount)>=n; }

static bool TransitionAllowed(State f,State t){
  if(f==t) return false;
  if(f!=COMPLETED && (t==PAUSE_SOFT||t==PAUSE_HARD||t==RECONCILE_REQUIRED||t==GLOBAL_STOP||t==COMPLETED)) return true;
  switch(f){
    case CORE_ONLY:return t==ARMED;
    case ARMED:return t==HEDGE_BUILDING;
    case HEDGE_BUILDING:return t==HEDGE_ACTIVE;
    case HEDGE_ACTIVE:return t==HEDGE_TP_PENDING;
    case HEDGE_TP_PENDING:return t==CORE_CLOSE_PENDING;
    case CORE_CLOSE_PENDING:return t==HEDGE_LOCK_PENDING;
    case HEDGE_LOCK_PENDING:return t==HEDGE_LOCKED;
    case HEDGE_LOCKED:return t==REHEDGE_PENDING;
    case REHEDGE_PENDING:return t==HEDGE_BUILDING;
    case PAUSE_SOFT:return t==ARMED||t==HEDGE_ACTIVE||t==HEDGE_LOCKED||t==REHEDGE_PENDING;
    case PAUSE_HARD: case RECONCILE_REQUIRED:return false;
    case GLOBAL_STOP:return t==COMPLETED;
    case COMPLETED:return t==CORE_ONLY;
  }
  return false;
}

static bool GapHit(Dir d,long anchor,long bid,long ask,long gap){
  if(anchor<=0||bid<=0||ask<=0||gap<0) return false;
  if(gap==0) return true;
  return d==BUY_CORE ? bid<=anchor-gap : ask>=anchor+gap;
}
static double Coverage(double core,double hedge){ return core<=0||hedge<=0?0:hedge/core*100; }
static double Corridor(Dir d,double coreBE,double hedgeBE){
  if(coreBE<=0||hedgeBE<=0) return 0;
  return d==BUY_CORE ? hedgeBE-coreBE : coreBE-hedgeBE;
}

struct Cycle{
  State state=CORE_ONLY; bool armed=false; int count=0; bool decision=false;
  int serial=1; int audit=0; long anchor=0; int armedDca=0;
};
static bool Arm(Cycle& c,int count,int n,bool evidence,long anchor){
  c.count=count;
  if(c.armed||c.state!=CORE_ONLY||!Threshold(count,n)||!evidence||anchor<=0) return false;
  c.state=ARMED;c.armed=true;c.anchor=anchor;c.armedDca=DcaCount(count);c.audit++;return true;
}
static void Observe(Cycle& c,int count){
  int prev=c.count;c.count=count;
  if(count==0&&prev>0&&c.armed&&c.state==ARMED){ c.state=COMPLETED;c.audit++; }
  if(c.state==COMPLETED&&count>0){ c=Cycle{};c.serial=2;c.count=count;c.audit=1; }
}
static bool ShadowDecision(Cycle& c,bool gapHit){
  if(!c.armed||c.state!=ARMED||c.decision||!gapHit) return false;
  c.decision=true;return true;
}

int main(){
  // N-DCA boundaries.
  Check("N0 flat false",!Threshold(0,0));
  Check("N0 initial true",Threshold(1,0));
  Check("N1 initial false",!Threshold(1,1));
  Check("N1 second true",Threshold(2,1));
  Check("N5 count5 false",!Threshold(5,5));
  Check("N5 count6 true",Threshold(6,5));
  Check("negative N false",!Threshold(100,-1));
  Check("DCA count initial zero",DcaCount(1)==0);
  Check("DCA count six five",DcaCount(6)==5);

  // State graph.
  Check("CORE->ARMED",TransitionAllowed(CORE_ONLY,ARMED));
  Check("CORE !->ACTIVE",!TransitionAllowed(CORE_ONLY,HEDGE_ACTIVE));
  Check("ARMED->BUILD",TransitionAllowed(ARMED,HEDGE_BUILDING));
  Check("BUILD->ACTIVE",TransitionAllowed(HEDGE_BUILDING,HEDGE_ACTIVE));
  Check("ACTIVE->TPP",TransitionAllowed(HEDGE_ACTIVE,HEDGE_TP_PENDING));
  Check("TPP->CORECLOSE",TransitionAllowed(HEDGE_TP_PENDING,CORE_CLOSE_PENDING));
  Check("CORECLOSE->LOCKP",TransitionAllowed(CORE_CLOSE_PENDING,HEDGE_LOCK_PENDING));
  Check("LOCKP->LOCKED",TransitionAllowed(HEDGE_LOCK_PENDING,HEDGE_LOCKED));
  Check("LOCKED->REHEDGE",TransitionAllowed(HEDGE_LOCKED,REHEDGE_PENDING));
  Check("REHEDGE->BUILD",TransitionAllowed(REHEDGE_PENDING,HEDGE_BUILDING));
  Check("any->RECONCILE",TransitionAllowed(ARMED,RECONCILE_REQUIRED));
  Check("HARD fail closed",!TransitionAllowed(PAUSE_HARD,ARMED));
  Check("RECON fail closed",!TransitionAllowed(RECONCILE_REQUIRED,ARMED));
  Check("GLOBAL->COMPLETE",TransitionAllowed(GLOBAL_STOP,COMPLETED));
  Check("COMPLETE->CORE next cycle",TransitionAllowed(COMPLETED,CORE_ONLY));
  Check("same state not transition",!TransitionAllowed(ARMED,ARMED));

  // Integer-tick adverse gap semantics.
  Check("BUY gap before false",!GapHit(BUY_CORE,420000,415001,415003,5000));
  Check("BUY gap boundary true",GapHit(BUY_CORE,420000,415000,415002,5000));
  Check("BUY through true",GapHit(BUY_CORE,420000,414900,414902,5000));
  Check("SELL gap before false",!GapHit(SELL_CORE,420000,424997,424999,5000));
  Check("SELL gap boundary true",GapHit(SELL_CORE,420000,424998,425000,5000));
  Check("SELL through true",GapHit(SELL_CORE,420000,425098,425100,5000));
  Check("gap0 immediate buy",GapHit(BUY_CORE,420000,430000,430002,0));
  Check("gap0 immediate sell",GapHit(SELL_CORE,420000,410000,410002,0));
  Check("negative gap invalid",!GapHit(BUY_CORE,420000,410000,410002,-1));

  // Coverage/corridor contract.
  CheckEq("coverage 1:1",Coverage(1,1),100);
  CheckEq("coverage diluted",Coverage(1.3,0.5),38.46153846153846,1e-10);
  CheckEq("coverage no core zero",Coverage(0,1),0);
  CheckEq("BUY corridor positive",Corridor(BUY_CORE,4190,4195),5);
  CheckEq("BUY corridor negative",Corridor(BUY_CORE,4200,4195),-5);
  CheckEq("SELL corridor positive",Corridor(SELL_CORE,4210,4205),5);
  CheckEq("SELL corridor negative",Corridor(SELL_CORE,4200,4205),-5);
  CheckEq("corridor missing BE zero",Corridor(BUY_CORE,4200,0),0);

  // Latch + parallel-cycle isolation.
  Cycle buy,sell;
  Check("buy no evidence no arm",!Arm(buy,6,5,false,420000));
  Check("buy arms exact threshold",Arm(buy,6,5,true,420000));
  Check("buy armed dca five",buy.armedDca==5);
  Observe(buy,3);
  Check("latch survives partial removal",buy.armed&&buy.state==ARMED);
  Check("sell still independent core",sell.state==CORE_ONLY&&!sell.armed);
  Check("sell arms independently",Arm(sell,2,1,true,425000));
  Check("buy decision once",ShadowDecision(buy,true));
  Check("buy decision not repeated",!ShadowDecision(buy,true));
  Check("sell decision unaffected",!sell.decision);
  Check("sell can decide separately",ShadowDecision(sell,true));
  Observe(buy,0);
  Check("buy flat completes",buy.state==COMPLETED);
  Check("sell remains armed",sell.state==ARMED&&sell.armed);

  // Bounded audit model: ring retains at most cap while total can grow.
  const int CAP=32; int total=0,stored=0;
  for(int i=0;i<100;i++){total++;stored=total<CAP?total:CAP;}
  Check("audit stored bounded 32",stored==32);
  Check("audit total preserved",total==100);

  printf("Recovery T3 shadow suite: %d passed, %d failed\n",pass_count,fail_count);
  return fail_count==0?0:1;
}
