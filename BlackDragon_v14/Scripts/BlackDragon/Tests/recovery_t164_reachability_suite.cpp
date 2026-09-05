// T16.4 Recovery reachability + Overlap preemption model regression.
#include <iostream>
using std::cout;
static int passed=0, failed=0;
#define CHECK(name,expr) do{if(expr){++passed;}else{++failed;cout<<"FAIL "<<name<<"\n";}}while(0)

enum Mode { OFF=0, SHADOW=1, ACTIVE=2 };
static int requiredCore(int start){return start<0?-1:start+1;}
static bool sideReachable(bool enabled,int maxOrders,int start){
  if(!enabled) return true;
  int req=requiredCore(start);
  if(req<1||maxOrders<1) return false;
  return req<=maxOrders;
}
static bool validate(Mode mode,bool buy,bool sell,int mb,int ms,int start){
  if(mode!=ACTIVE) return true;
  return sideReachable(buy,mb,start)&&sideReachable(sell,ms,start);
}
static bool overlapMayPreempt(bool overlap,int from,int start){
  if(!overlap||from<1||start<0)return false;
  return from<requiredCore(start);
}

int main(){
  CHECK("start0 requires1",requiredCore(0)==1);
  CHECK("start7 requires8",requiredCore(7)==8);
  CHECK("start13 requires14",requiredCore(13)==14);
  CHECK("negative invalid",requiredCore(-1)==-1);

  CHECK("Max8 Start7 reachable",sideReachable(true,8,7));
  CHECK("Max8 Start8 unreachable",!sideReachable(true,8,8));
  CHECK("Max8 Start13 unreachable",!sideReachable(true,8,13));
  CHECK("disabled side ignored",sideReachable(false,1,99));
  CHECK("zero max invalid enabled",!sideReachable(true,0,0));

  CHECK("ACTIVE both valid",validate(ACTIVE,true,true,8,8,7));
  CHECK("ACTIVE buy invalid",!validate(ACTIVE,true,false,8,1,13));
  CHECK("ACTIVE sell invalid",!validate(ACTIVE,false,true,1,8,13));
  CHECK("ACTIVE disabled invalid side ignored",validate(ACTIVE,true,false,8,1,7));
  CHECK("OFF preserves legacy config",validate(OFF,true,true,1,1,99));
  CHECK("SHADOW remains observational",validate(SHADOW,true,true,1,1,99));

  CHECK("Overlap6 preempts required14",overlapMayPreempt(true,6,13));
  CHECK("Overlap8 preempts required14",overlapMayPreempt(true,8,13));
  CHECK("Overlap14 same threshold not preempt",!overlapMayPreempt(true,14,13));
  CHECK("Overlap15 after threshold no preempt",!overlapMayPreempt(true,15,13));
  CHECK("Overlap disabled no warning",!overlapMayPreempt(false,6,13));

  cout<<"Recovery T16.4 reachability model: "<<passed<<" passed, "<<failed<<" failed\n";
  if(failed==0) cout<<"ALL GREEN — T16.4 reachability/Overlap boundary policy passed.\n";
  return failed==0?0:1;
}
