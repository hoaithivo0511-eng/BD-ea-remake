// Adaptive Recovery Hedge T2 — execution ownership/reconcile offline suite.
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <string>
#include <vector>
using namespace std;

static int g_pass=0, g_fail=0;
static void Check(const char *name, bool ok){ if(ok){g_pass++;return;} g_fail++; printf("FAIL: %s\n",name); }
static void CheckEq(const char *name,double got,double want,double eps=1e-9){ Check(name,fabs(got-want)<=eps); }

enum Policy { LEGACY_RELEASE=0, FAIL_CLOSED=1 };
enum Cmd { LEGACY=0, REC_OPEN, REC_CLOSE, REC_MODIFY };
enum Rc { REQUOTE=10004, PRICE_CHANGED=10020, PRICE_OFF=10021, TIMEOUT=10012, CONNECTION=10031, INVALID=10013 };

static bool OwnerMatches(long observed,long owner){ return observed==owner; }
static bool Retryable(unsigned rc){ return rc==REQUOTE||rc==PRICE_CHANGED||rc==PRICE_OFF||rc==TIMEOUT||rc==CONNECTION; }
static bool Ambiguous(unsigned rc){ return rc==TIMEOUT||rc==CONNECTION; }
static bool RetryAllowed(Policy p,unsigned rc){ if(!Retryable(rc)) return false; if(p==FAIL_CLOSED&&Ambiguous(rc)) return false; return true; }

static double CloseFloor(double requested,double current,double vmin,double step){
  if(requested<=0||current<=0||vmin<=0||step<=0) return 0;
  double eps=step*1e-7;
  if(requested+eps>=current) return round(current*1e8)/1e8;
  long units=(long)floor(requested/step+1e-9);
  double target=units*step;
  if(target+eps<vmin) return 0;
  if(target>requested+eps){ units--; if(units<=0) return 0; target=units*step; }
  double remaining=current-target;
  if(remaining>eps&&remaining+eps<vmin){
    double maxTarget=current-vmin;
    long maxUnits=(long)floor(maxTarget/step+1e-9);
    target=maxUnits*step;
    if(target>requested+eps){ long reqUnits=(long)floor(requested/step+1e-9); target=reqUnits*step; }
  }
  if(target<=0||target>requested+eps) return 0;
  return round(target*1e8)/1e8;
}

static bool CloseResolved(double before,double current,double target,double step){
  if(target<=0) return false;
  double eps=step>0?step*0.5:1e-9;
  return before-current+eps>=target;
}

struct Pos { long magic; int dir; string sym; };
static int CountOpen(const vector<Pos>&p,int dir,const string&sym,long magic){
  int n=0; for(auto &x:p) if(x.dir==dir&&x.sym==sym&&x.magic==magic) n++; return n;
}

struct Pending {
  int cycle=0; Cmd cmd=LEGACY; Policy policy=LEGACY_RELEASE; bool active=true;
  bool reconcile=false; bool stateResolved=false;
};
static void WatchdogHard(Pending &p){
  if(!p.active||p.stateResolved){ p.active=false; p.reconcile=false; return; }
  if(p.policy==FAIL_CLOSED){ p.reconcile=true; return; }
  p.active=false;
}
static void Reconcile(Pending &p,bool stateResolved){ p.stateResolved=stateResolved; if(stateResolved){p.active=false;p.reconcile=false;} }

int main(){
  Check("owner exact core",OwnerMatches(1111,1111));
  Check("owner exact recovery",OwnerMatches(20260807,20260807));
  Check("owner core != recovery",!OwnerMatches(1111,20260807));
  Check("manual magic0 exact",OwnerMatches(0,0));
  Check("manual != core",!OwnerMatches(0,1111));

  Check("legacy requote retry",RetryAllowed(LEGACY_RELEASE,REQUOTE));
  Check("legacy timeout retry",RetryAllowed(LEGACY_RELEASE,TIMEOUT));
  Check("legacy connection retry",RetryAllowed(LEGACY_RELEASE,CONNECTION));
  Check("strict requote retry",RetryAllowed(FAIL_CLOSED,REQUOTE));
  Check("strict price-changed retry",RetryAllowed(FAIL_CLOSED,PRICE_CHANGED));
  Check("strict price-off retry",RetryAllowed(FAIL_CLOSED,PRICE_OFF));
  Check("strict timeout NO blind retry",!RetryAllowed(FAIL_CLOSED,TIMEOUT));
  Check("strict connection NO blind retry",!RetryAllowed(FAIL_CLOSED,CONNECTION));
  Check("invalid never retry",!RetryAllowed(FAIL_CLOSED,INVALID));

  CheckEq("close floor .245->.24",CloseFloor(.245,1.0,.01,.01),.24,1e-12);
  CheckEq("close exact .30",CloseFloor(.30,1.0,.01,.10),.30,1e-12);
  CheckEq("close never rounds .349 step .10",CloseFloor(.349,1.0,.10,.10),.30,1e-12);
  CheckEq("close full exact",CloseFloor(1.0,1.0,.01,.01),1.0,1e-12);
  CheckEq("close request over current => full only",CloseFloor(2.0,1.0,.01,.01),1.0,1e-12);
  CheckEq("close below broker min rejected",CloseFloor(.005,1.0,.01,.01),0.0,1e-12);
  CheckEq("close keeps min remainder",CloseFloor(.095,.10,.01,.01),.09,1e-12);
  CheckEq("close .099 keeps min remainder",CloseFloor(.099,.10,.01,.01),.09,1e-12);
  CheckEq("close invalid step",CloseFloor(.10,1.0,.01,0),0.0,1e-12);
  Check("target <= requested",CloseFloor(.247,1.0,.01,.01)<=.247+1e-12);

  Check("partial close target resolved",CloseResolved(.10,.06,.04,.01));
  Check("partial close insufficient unresolved",!CloseResolved(.10,.08,.04,.01));
  Check("full close resolved",CloseResolved(.10,0,.10,.01));
  Check("zero target unresolved",!CloseResolved(.10,.10,0,.01));

  vector<Pos> p={{1111,0,"XAUUSD"},{1111,0,"XAUUSD"},{20260807,0,"XAUUSD"},{20260807,1,"XAUUSD"},{1111,0,"EURUSD"}};
  Check("count Core owner only",CountOpen(p,0,"XAUUSD",1111)==2);
  Check("count Recovery owner only",CountOpen(p,0,"XAUUSD",20260807)==1);
  Check("count Recovery opposite dir",CountOpen(p,1,"XAUUSD",20260807)==1);
  Check("count symbol isolated",CountOpen(p,0,"EURUSD",1111)==1);

  Pending legacy{0,LEGACY,LEGACY_RELEASE,true,false,false};
  WatchdogHard(legacy);
  Check("legacy hard timeout releases",!legacy.active&&!legacy.reconcile);
  Pending strict{101,REC_OPEN,FAIL_CLOSED,true,false,false};
  WatchdogHard(strict);
  Check("strict hard timeout stays active",strict.active);
  Check("strict hard timeout flags reconcile",strict.reconcile);
  Reconcile(strict,true);
  Check("strict later state proof completes",!strict.active&&!strict.reconcile);

  Pending buy{101,REC_OPEN,FAIL_CLOSED,true,false,false};
  Pending sell{202,REC_OPEN,FAIL_CLOSED,true,false,false};
  WatchdogHard(buy);
  Check("BUY cycle reconcile flagged",buy.reconcile&&buy.active);
  Check("SELL parallel cycle untouched",sell.active&&!sell.reconcile);
  Reconcile(buy,true);
  Check("BUY reconcile does not mutate SELL",!buy.active&&sell.active&&!sell.reconcile);

  printf("Recovery T2 execution suite: %d passed, %d failed\n",g_pass,g_fail);
  return g_fail==0?0:1;
}
