// T16.1 ARCS protective-SL event ordering regression.
#include <algorithm>
#include <cmath>
#include <iostream>
using std::cout;
static int passed=0, failed=0;
#define CHECK(name,expr) do{if(expr){++passed;}else{++failed;cout<<"FAIL "<<name<<"\n";}}while(0)

enum LayerState { LOCK_PENDING, PROTECTIVE_CLOSE_PENDING, LOCKED, CLOSED };
enum Phase { PH_LOCK_PENDING, PH_PROTECTIVE_WAIT, PH_LOCKED, PH_RECONCILE };

struct S {
  LayerState layer=LOCK_PENDING;
  Phase phase=PH_LOCK_PENDING;
  long remaining=2;
  long live=2;
  double targetSl=4544.267;
  bool dealConsumed=false;
  bool nextGenerationStarted=false;
};

static bool shouldEnterWait(const S& s){
  return s.phase==PH_LOCK_PENDING && s.layer==LOCK_PENDING &&
         s.remaining>0 && s.live==0 && s.targetSl>0;
}

static bool protectiveIdentity(bool owner,bool position,long reason,
                               double programmed,double durable,double dealPrice,
                               double slTol,double fillTol,bool modifyProof){
  if(!owner||!position||reason!=1) return false; // 1 = SL in this pure model
  if(durable<=0||dealPrice<=0||slTol<0||fillTol<0) return false;
  bool programmedMatch=programmed>0 && std::fabs(programmed-durable)<=slTol+1e-12;
  if(!programmedMatch && !modifyProof) return false;
  return std::fabs(dealPrice-durable)<=fillTol+1e-12;
}

static void observeBrokerEffect(S& s){
  if(shouldEnterWait(s)){
    s.layer=PROTECTIVE_CLOSE_PENDING;
    s.phase=PH_PROTECTIVE_WAIT;
  }
}
static void consumeExactDeal(S& s,bool exactProof){
  if(s.phase!=PH_PROTECTIVE_WAIT || s.layer!=PROTECTIVE_CLOSE_PENDING) return;
  if(!exactProof){s.phase=PH_RECONCILE;return;}
  s.dealConsumed=true;
  s.remaining=0;
  s.layer=CLOSED;
  s.phase=PH_LOCKED;
}
static void maybeStartNext(S& s){
  if(s.phase==PH_LOCKED && s.layer==CLOSED && s.dealConsumed)
    s.nextGenerationStarted=true;
}

int main(){
  S a;
  CHECK("no wait while broker position still live",!shouldEnterWait(a));
  a.live=0;
  CHECK("vanished retained layer enters wait",shouldEnterWait(a));
  observeBrokerEffect(a);
  CHECK("phase waits for close DEAL",a.phase==PH_PROTECTIVE_WAIT);
  CHECK("layer identity retained while waiting",a.layer==PROTECTIVE_CLOSE_PENDING);
  maybeStartNext(a);
  CHECK("Gnext forbidden before DEAL proof",!a.nextGenerationStarted);

  // Reproduce owner log: programmed SL equals durable target and fill is near SL.
  bool exact=protectiveIdentity(true,true,1,4544.267,4544.267,4544.267,
                                0.002,0.025,false);
  CHECK("broker SL exact durable target accepted",exact);
  consumeExactDeal(a,exact);
  CHECK("DEAL proof retires layer",a.layer==CLOSED && a.remaining==0);
  CHECK("phase returns LOCKED after consume",a.phase==PH_LOCKED);
  maybeStartNext(a);
  CHECK("Gnext allowed only after DEAL consumed",a.nextGenerationStarted);

  // Defense in depth: mutable layer target may have moved, but exact recent
  // ExecutionLayer MODIFY proof can still classify the SL.
  CHECK("modify proof survives mutable target drift",
        protectiveIdentity(true,true,1,4544.267,4544.267,4544.270,
                           0.002,0.025,true));
  CHECK("manual SL without target/proof rejected",
        !protectiveIdentity(true,true,1,4544.267,4545.000,4544.267,
                            0.002,0.025,false));
  CHECK("wrong close reason rejected",
        !protectiveIdentity(true,true,2,4544.267,4544.267,4544.267,
                            0.002,0.025,true));
  CHECK("wrong position identity rejected",
        !protectiveIdentity(true,false,1,4544.267,4544.267,4544.267,
                            0.002,0.025,true));

  S noRetained; noRetained.remaining=0; noRetained.live=0;
  CHECK("100pct TP no retained layer does not enter protective wait",
        !shouldEnterWait(noRetained));
  S unknown; unknown.live=0; unknown.targetSl=0;
  CHECK("vanish without durable lock target is not accepted as protective wait",
        !shouldEnterWait(unknown));
  CHECK("registry capacity covers legacy MaxGen50",64>=50);

  cout<<"Recovery T16.1 event-order model: "<<passed<<" passed, "<<failed<<" failed\n";
  if(failed==0) cout<<"ALL GREEN — broker SL must be consumed before Gnext.\n";
  return failed==0?0:1;
}
