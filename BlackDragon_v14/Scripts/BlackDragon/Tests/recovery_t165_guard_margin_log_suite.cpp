// T16.5 Guard-scope / capacity-wait / margin-reserve pure regression.
#include <algorithm>
#include <cmath>
#include <iostream>
using std::cout;
static int passed=0, failed=0;
#define CHECK(name,expr) do{if(expr){++passed;}else{++failed;cout<<"FAIL "<<name<<"\n";}}while(0)

enum Cap { EXECUTE=0, WAIT_NO_EFFECT=1, RECONCILE=2 };
static Cap capacity(bool preflight,bool accepted,bool ambiguous){
  if(ambiguous) return RECONCILE;
  if(!preflight || !accepted) return WAIT_NO_EFFECT;
  return EXECUTE;
}
static double side(double core,double hedge){return core+hedge;}
static double magicNet(double cb,double cs,double hb,double hs){return side(cb,hb)+side(cs,hs);}
static bool pctDiff(double buy,double sell,double pct){
  if(pct<=0) return false;
  double win=std::max(buy,sell), lose=std::min(buy,sell);
  if(lose>=0) return false;
  return win + lose*(1.0+pct/100.0) >= 0;
}
static bool reserve(double freeM,double dca,double hedge){
  if(freeM<0||dca<0||hedge<0) return false;
  return freeM+1e-9>=dca+hedge;
}
static int waitSec(int x){if(x<0)return 0;if(x>86400)return 86400;return x;}

int main(){
  // Runtime incident: Core-only PctDiff looked profitable (+6.45/-2.19), but
  // BUY Core's Recovery SELL Hedge carried about -1466.60 economic P/L.
  CHECK("legacy core-only pctdiff would fire", pctDiff(6.45,-2.19,3.5));
  double buyEconomic=side(6.45,-1466.60);
  double sellEconomic=side(-2.19,0.0);
  CHECK("economic buy includes Recovery hedge", std::fabs(buyEconomic+1460.15)<1e-9);
  CHECK("economic pctdiff must not fire", !pctDiff(buyEconomic,sellEconomic,3.5));
  CHECK("economic magic net includes hedge",
        std::fabs(magicNet(6.45,-2.19,-1466.60,0.0)+1462.34)<1e-9);
  CHECK("side profit neutral helper", std::fabs(side(10.0,-4.0)-6.0)<1e-9);

  // Known no-effect capacity failures are waits, never reconcile.
  CHECK("preflight margin fail waits", capacity(false,false,false)==WAIT_NO_EFFECT);
  CHECK("explicit broker reject waits", capacity(true,false,false)==WAIT_NO_EFFECT);
  CHECK("accepted request executes", capacity(true,true,false)==EXECUTE);
  CHECK("ambiguous timeout reconciles", capacity(true,false,true)==RECONCILE);
  CHECK("ambiguous dominates accepted flag", capacity(true,true,true)==RECONCILE);

  // DCA reserve: free margin must cover DCA + projected mandatory Hedge.
  CHECK("reserve exact boundary", reserve(1000,250,750));
  CHECK("reserve above boundary", reserve(1001,250,750));
  CHECK("reserve blocks shortfall", !reserve(999,250,750));
  CHECK("reserve zero hedge allowed", reserve(250,250,0));
  CHECK("reserve invalid negative free", !reserve(-1,0,0));
  CHECK("reserve invalid negative component", !reserve(100,-1,10));

  // Logging control: expected waits can be reduced without suppressing first
  // state-transition/order/error evidence.
  CHECK("wait log default passthrough", waitSec(900)==900);
  CHECK("wait log zero supported", waitSec(0)==0);
  CHECK("wait log negative clamps zero", waitSec(-5)==0);
  CHECK("wait log max clamps day", waitSec(999999)==86400);

  cout<<"Recovery T16.5 guard/margin/log model: "<<passed<<" passed, "<<failed<<" failed\n";
  if(failed==0) cout<<"ALL GREEN — T16.5 scope/capacity/log policy passed.\n";
  return failed==0?0:1;
}
