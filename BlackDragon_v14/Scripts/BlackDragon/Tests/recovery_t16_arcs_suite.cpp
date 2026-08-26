// T16 ARCS stacked Recovery — standalone pure model regression.
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <iostream>
using std::cout;
static int passed=0, failed=0;
#define CHECK(name,expr) do{if(expr){++passed;}else{++failed;cout<<"FAIL "<<name<<"\n";}}while(0)

enum Policy { HEDGE_CAN_BANG=0, ARCS_XEP_LOP=1 };
enum Dir { CORE_BUY=0, CORE_SELL=1 };

static long pctUnits(long core,double pct){
  if(core<=0||pct<=0) return 0;
  return (long)std::floor((double)core*pct/100.0+1e-9);
}
static long newGen(Policy p,long core,long existing,double pct){
  long desired=pctUnits(core,pct);
  if(desired<=0) return 0;
  if(p==ARCS_XEP_LOP) return desired;
  existing=std::max(0L,existing);
  return desired>existing?desired-existing:0;
}
static long partial(long active,double pct,long minU){
  if(active<=0||pct<=0||pct>100||minU<=0) return 0;
  if(pct>=100.0-1e-12) return active;
  long target=(long)std::floor((double)active*pct/100.0+1e-9);
  if(target<minU) return 0;
  if(target>=active) return active;
  long rem=active-target;
  if(rem>0&&rem<minU){target=active-minU;if(target<minU)return 0;}
  return target;
}
static bool virtualHit(Dir d,double bid,double ask,double sl){
  if(bid<=0||ask<=0||sl<=0)return false;
  return d==CORE_BUY?ask>=sl:bid<=sl;
}
static bool virtualArm(Dir d,double bid,double ask,double sl){
  if(bid<=0||ask<=0||sl<=0)return false;
  return d==CORE_BUY?sl>ask:sl<bid;
}
static double globalFold(Dir d,double acc,double candidate){
  if(candidate<=0)return acc;
  if(acc<=0)return candidate;
  return d==CORE_BUY?std::min(acc,candidate):std::max(acc,candidate);
}
static long maxCoreByCash(double credit,double lossPerUnit,long positionUnits){
  if(credit<=0||lossPerUnit<=0||positionUnits<=0)return 0;
  long units=(long)std::floor(credit/lossPerUnit+1e-9);
  return std::min(units,positionUnits);
}

int main(){
  // New % volume input: floor-only, both under- and over-hedge are legal.
  CHECK("pct 25 of 100",pctUnits(100,25)==25);
  CHECK("pct 50 of 100",pctUnits(100,50)==50);
  CHECK("pct 80 of 100",pctUnits(100,80)==80);
  CHECK("pct 100 of 100",pctUnits(100,100)==100);
  CHECK("pct 120 of 100",pctUnits(100,120)==120);
  CHECK("pct 150 of 75 floors",pctUnits(75,150)==112);
  CHECK("pct 33 of 75 floors",pctUnits(75,33)==24);
  CHECK("zero pct invalid",pctUnits(75,0)==0);
  CHECK("zero core invalid",pctUnits(0,100)==0);

  // Compatibility policy versus source-of-truth stacked ARCS policy.
  CHECK("balance core75 existing50 pct100 opens25",newGen(HEDGE_CAN_BANG,75,50,100)==25);
  CHECK("stack core75 existing50 pct100 opens75",newGen(ARCS_XEP_LOP,75,50,100)==75);
  CHECK("balance core75 existing50 pct120 opens40",newGen(HEDGE_CAN_BANG,75,50,120)==40);
  CHECK("stack core75 existing50 pct120 opens90",newGen(ARCS_XEP_LOP,75,50,120)==90);
  CHECK("balance over-covered opens zero",newGen(HEDGE_CAN_BANG,75,100,100)==0);
  CHECK("stack ignores retained layers",newGen(ARCS_XEP_LOP,75,100,100)==75);

  // Canonical owner oracle: 1.00 Core -> G1 1.00 -> close 0.50 Hedge.
  // +250c funds exactly 0.25 Core in the owner's simplified example.
  long core=100, g1=100;
  long g1Close=partial(g1,50,1);
  long g1Retained=g1-g1Close;
  long fundedCore=maxCoreByCash(250.0,10.0,core); // 10c loss per 0.01 unit -> 25 units
  long coreResidual=core-fundedCore;
  long g2=newGen(ARCS_XEP_LOP,coreResidual,g1Retained,100);
  long totalHedge=g1Retained+g2;
  long netSell=totalHedge-coreResidual;
  CHECK("oracle G1 close50",g1Close==50);
  CHECK("oracle retained G1 50",g1Retained==50);
  CHECK("oracle realized cash funds Core25",fundedCore==25);
  CHECK("oracle Core residual75",coreResidual==75);
  CHECK("oracle G2 must be75 not25",g2==75);
  CHECK("oracle total Hedge125",totalHedge==125);
  CHECK("oracle net trend SELL50",netSell==50);

  // TP scope is ACTIVE GENERATION only, never G1+G2 aggregate.
  CHECK("G2 active75 partial50 floors37",partial(75,50,1)==37);
  CHECK("aggregate125 would be62 and is forbidden oracle",partial(125,50,1)==62);
  CHECK("min volume prevents sub-min partial",partial(1,50,1)==0);

  // Virtual SL direction: BUY Core owns SELL Hedge; SELL Core owns BUY Hedge.
  CHECK("SELL hedge virtual SL arms above ask",virtualArm(CORE_BUY,4190.0,4190.1,4194.7));
  CHECK("SELL hedge virtual SL not hit below",!virtualHit(CORE_BUY,4194.5,4194.6,4194.7));
  CHECK("SELL hedge virtual SL hits by ask",virtualHit(CORE_BUY,4194.6,4194.7,4194.7));
  CHECK("BUY hedge virtual SL arms below bid",virtualArm(CORE_SELL,4209.9,4210.0,4205.3));
  CHECK("BUY hedge virtual SL not hit above",!virtualHit(CORE_SELL,4205.4,4205.5,4205.3));
  CHECK("BUY hedge virtual SL hits by bid",virtualHit(CORE_SELL,4205.3,4205.4,4205.3));

  // One Global SL must be safe for every layer: SELL chooses lower target;
  // BUY chooses higher target.
  double sellGlobal=0;
  sellGlobal=globalFold(CORE_BUY,sellGlobal,4194.7);
  sellGlobal=globalFold(CORE_BUY,sellGlobal,4189.7);
  sellGlobal=globalFold(CORE_BUY,sellGlobal,4184.7);
  CHECK("SELL global chooses lowest safe target",std::fabs(sellGlobal-4184.7)<1e-9);
  double buyGlobal=0;
  buyGlobal=globalFold(CORE_SELL,buyGlobal,4205.3);
  buyGlobal=globalFold(CORE_SELL,buyGlobal,4210.3);
  CHECK("BUY global chooses highest safe target",std::fabs(buyGlobal-4210.3)<1e-9);

  cout<<"Recovery T16 ARCS model: "<<passed<<" passed, "<<failed<<" failed\n";
  if(failed==0) cout<<"ALL GREEN — T16 stacked sizing/TP-scope/SL oracle passed.\n";
  return failed==0?0:1;
}
