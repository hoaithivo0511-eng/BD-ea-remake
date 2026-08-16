#include <iostream>
#include <string>
#include <vector>
#include <algorithm>
using std::cout;

static int passed=0, failed=0;
#define CHECK(name, expr) do { if(expr){++passed;} else {++failed; cout << "FAIL " << name << "\n";} } while(0)

enum State { CORE_ONLY, ARMED, HEDGE_BUILDING, HEDGE_ACTIVE, HEDGE_TP_PENDING, CORE_CLOSE_PENDING,
             HEDGE_LOCK_PENDING, HEDGE_LOCKED, REHEDGE_PENDING, PAUSE_SOFT, PAUSE_HARD,
             RECONCILE_REQUIRED, GLOBAL_STOP, COMPLETED };
enum Step { NONE, TRIM_HEDGE, CLOSE_CORE, COMPLETE, RECONCILE_HOLD };

bool StateNeeds(State s){ return s!=CORE_ONLY && s!=ARMED && s!=COMPLETED; }
long PostCore(long cur,long close){ if(cur<=0) return 0; if(close<=0) return cur; return close>=cur?0:cur-close; }
long Cap(long cur,long target,bool external){ cur=std::max(0L,cur); if(external) return cur; target=std::max(0L,target); return std::min(cur,target); }
long Excess(long cur,long target,long hedge,bool external){ if(hedge<=0)return 0; long cap=Cap(cur,target,external); return hedge>cap?hedge-cap:0; }
long TrimReq(long excess,long ticket,long minU){ if(excess<=0||ticket<=0||minU<=0)return 0; if(excess<minU)return ticket; return std::min(excess,ticket); }
Step Next(bool external,long cur,long target,long hedge,bool managedLive){ if(Excess(cur,target,hedge,external)>0)return TRIM_HEDGE; if(external){ if(cur<=0&&hedge<=0)return COMPLETE; return RECONCILE_HOLD;} if(managedLive||cur>target)return CLOSE_CORE; if(hedge>cur)return TRIM_HEDGE; return COMPLETE; }

int main(){
  CHECK("CORE_ONLY bypass", !StateNeeds(CORE_ONLY));
  CHECK("ARMED bypass", !StateNeeds(ARMED));
  CHECK("COMPLETED bypass", !StateNeeds(COMPLETED));
  CHECK("BUILDING coord", StateNeeds(HEDGE_BUILDING));
  CHECK("ACTIVE coord", StateNeeds(HEDGE_ACTIVE));
  CHECK("TP_PENDING coord", StateNeeds(HEDGE_TP_PENDING));
  CHECK("CORE_CLOSE coord", StateNeeds(CORE_CLOSE_PENDING));
  CHECK("LOCK_PENDING coord", StateNeeds(HEDGE_LOCK_PENDING));
  CHECK("LOCKED coord", StateNeeds(HEDGE_LOCKED));
  CHECK("REHEDGE coord", StateNeeds(REHEDGE_PENDING));
  CHECK("PAUSE_SOFT coord", StateNeeds(PAUSE_SOFT));
  CHECK("PAUSE_HARD coord", StateNeeds(PAUSE_HARD));
  CHECK("RECONCILE coord", StateNeeds(RECONCILE_REQUIRED));
  CHECK("GLOBAL coord", StateNeeds(GLOBAL_STOP));

  CHECK("post full", PostCore(1237,1237)==0);
  CHECK("post over", PostCore(1237,2000)==0);
  CHECK("post partial", PostCore(1237,237)==1000);
  CHECK("post zero close", PostCore(1237,0)==1237);
  CHECK("post flat", PostCore(0,200)==0);

  CHECK("full hedge cap zero", Cap(1237,0,false)==0);
  CHECK("overlap cap target", Cap(1237,1000,false)==1000);
  CHECK("target above current cap current", Cap(800,1000,false)==800);
  CHECK("external cap current", Cap(800,0,true)==800);
  CHECK("negative core cap zero", Cap(-1,100,true)==0);

  CHECK("full excess all hedge", Excess(1237,0,1237,false)==1237);
  CHECK("overlap excess 237", Excess(1237,1000,1237,false)==237);
  CHECK("overlap no excess", Excess(1237,1000,800,false)==0);
  CHECK("external core shrink excess", Excess(800,0,1000,true)==200);
  CHECK("external underhedge no excess", Excess(1000,0,800,true)==0);
  CHECK("flat core naked hedge", Excess(0,0,500,true)==500);

  CHECK("trim normal", TrimReq(618,500,1)==500);
  CHECK("trim residual", TrimReq(118,500,1)==118);
  CHECK("trim submin closes child", TrimReq(1,5,2)==5);
  CHECK("trim exact min", TrimReq(2,5,2)==2);
  CHECK("trim invalid", TrimReq(0,5,2)==0);

  CHECK("full first trims hedge", Next(false,1237,0,1237,false)==TRIM_HEDGE);
  CHECK("full then closes core", Next(false,1237,0,0,false)==CLOSE_CORE);
  CHECK("full keeps closing managed manual", Next(false,0,0,0,true)==CLOSE_CORE);
  CHECK("full completes only when managed side flat", Next(false,0,0,0,false)==COMPLETE);
  CHECK("overlap trims only excess", Next(false,1237,1000,1237,true)==TRIM_HEDGE);
  CHECK("overlap closes ticket after trim", Next(false,1237,1000,1000,true)==CLOSE_CORE);
  CHECK("overlap complete at target", Next(false,1000,1000,1000,false)==COMPLETE);
  CHECK("unexpected extra core close trims again", Next(false,900,1000,1000,false)==TRIM_HEDGE);
  CHECK("external trims excess", Next(true,800,0,1000,false)==TRIM_HEDGE);
  CHECK("external safe exposure holds reconcile", Next(true,800,0,800,false)==RECONCILE_HOLD);
  CHECK("external underhedged holds reconcile", Next(true,800,0,500,false)==RECONCILE_HOLD);
  CHECK("external flat completes", Next(true,0,0,0,false)==COMPLETE);

  long buyCore=1000,buyHedge=700,sellCore=500,sellHedge=600;
  CHECK("buy cycle no cross excess", Excess(buyCore,buyCore,buyHedge,true)==0);
  CHECK("sell cycle own excess", Excess(sellCore,sellCore,sellHedge,true)==100);
  CHECK("buy unchanged by sell", Excess(buyCore,buyCore,buyHedge,true)==0);

  cout << passed << " passed, " << failed << " failed\n";
  return failed==0?0:1;
}
