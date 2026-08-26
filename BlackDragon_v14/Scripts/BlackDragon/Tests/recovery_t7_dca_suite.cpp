#include <cmath>
#include <iostream>
#include <string>

static int passed=0, failed=0;
#define CHECK(name, expr) do { if(expr){++passed;} else {++failed; std::cerr<<"FAIL "<<name<<"\n";} } while(0)

enum Mode { OFF=0, SHADOW=1, ACTIVE=2 };
enum Dir { CORE_BUY=0, CORE_SELL=1 };
enum State {
 CORE_ONLY=0, ARMED, HEDGE_BUILDING, HEDGE_ACTIVE, HEDGE_TP_PENDING,
 CORE_CLOSE_PENDING, HEDGE_LOCK_PENDING, HEDGE_LOCKED, REHEDGE_PENDING,
 PAUSE_SOFT, PAUSE_HARD, RECONCILE_REQUIRED, GLOBAL_STOP, COMPLETED
};

bool postStable(State s){ return s==HEDGE_ACTIVE||s==HEDGE_LOCKED||s==REHEDGE_PENDING; }
bool stateAllows(Mode m,bool cont,State s){
 if(m!=ACTIVE) return true;
 if(s==CORE_ONLY||s==ARMED) return true;
 if(postStable(s)) return cont;
 return false;
}
double coverage(double core,double hedge){ if(core<=0||hedge<=0) return 0; return hedge/core*100.0; }
bool coverageAllows(double minPct,double core,double hedge){
 if(minPct<=0) return true;
 if(core<=0) return false;
 return coverage(core,hedge)+1e-9>=minPct;
}
double corridorPrice(Dir d,double coreBE,double hedgeBE){
 if(coreBE<=0||hedgeBE<=0) return 0;
 return d==CORE_BUY ? hedgeBE-coreBE : coreBE-hedgeBE;
}
double corridorPips(Dir d,double coreBE,double hedgeBE,double pip){ if(pip<=0) return 0; return corridorPrice(d,coreBE,hedgeBE)/pip; }
bool corridorAllows(double target,Dir d,double coreBE,double hedgeBE,double pip){
 if(target<=0) return true;
 if(pip<=0||coreBE<=0||hedgeBE<=0) return false;
 return corridorPips(d,coreBE,hedgeBE,pip)+1e-9<target;
}
bool gate(Mode m,bool cont,State s,double minCov,double target,Dir d,double coreLots,double coreBE,double hedgeLots,double hedgeBE,double pip){
 if(!stateAllows(m,cont,s)) return false;
 if(m!=ACTIVE) return true;
 if(!postStable(s)) return true;
 return coverageAllows(minCov,coreLots,hedgeLots)&&corridorAllows(target,d,coreBE,hedgeBE,pip);
}

int main(){
 CHECK("off-any", gate(OFF,false,GLOBAL_STOP,99,1,CORE_BUY,1,4200,0,0,.1));
 CHECK("shadow-any", gate(SHADOW,false,HEDGE_BUILDING,99,1,CORE_BUY,1,4200,0,0,.1));
 CHECK("active-core-only", gate(ACTIVE,false,CORE_ONLY,90,10,CORE_BUY,1,4200,0,0,.1));
 CHECK("active-armed", gate(ACTIVE,false,ARMED,90,10,CORE_BUY,1,4200,0,0,.1));
 CHECK("off-blocks-active", !gate(ACTIVE,false,HEDGE_ACTIVE,0,0,CORE_BUY,1,4200,1,4210,.1));
 CHECK("off-blocks-locked", !gate(ACTIVE,false,HEDGE_LOCKED,0,0,CORE_BUY,1,4200,1,4210,.1));
 CHECK("off-blocks-rehedge", !gate(ACTIVE,false,REHEDGE_PENDING,0,0,CORE_BUY,1,4200,1,4210,.1));
 CHECK("on-active", gate(ACTIVE,true,HEDGE_ACTIVE,0,0,CORE_BUY,1,4200,1,4210,.1));
 CHECK("on-locked", gate(ACTIVE,true,HEDGE_LOCKED,0,0,CORE_BUY,1,4200,1,4210,.1));
 CHECK("on-rehedge", gate(ACTIVE,true,REHEDGE_PENDING,0,0,CORE_BUY,1,4200,1,4210,.1));
 CHECK("block-building", !gate(ACTIVE,true,HEDGE_BUILDING,0,0,CORE_BUY,1,4200,1,4210,.1));
 CHECK("block-tp-pending", !gate(ACTIVE,true,HEDGE_TP_PENDING,0,0,CORE_BUY,1,4200,1,4210,.1));
 CHECK("block-core-close", !gate(ACTIVE,true,CORE_CLOSE_PENDING,0,0,CORE_BUY,1,4200,1,4210,.1));
 CHECK("block-lock-pending", !gate(ACTIVE,true,HEDGE_LOCK_PENDING,0,0,CORE_BUY,1,4200,1,4210,.1));
 CHECK("block-pause-soft", !gate(ACTIVE,true,PAUSE_SOFT,0,0,CORE_BUY,1,4200,1,4210,.1));
 CHECK("block-pause-hard", !gate(ACTIVE,true,PAUSE_HARD,0,0,CORE_BUY,1,4200,1,4210,.1));
 CHECK("block-reconcile", !gate(ACTIVE,true,RECONCILE_REQUIRED,0,0,CORE_BUY,1,4200,1,4210,.1));
 CHECK("block-global", !gate(ACTIVE,true,GLOBAL_STOP,0,0,CORE_BUY,1,4200,1,4210,.1));
 CHECK("block-completed", !gate(ACTIVE,true,COMPLETED,0,0,CORE_BUY,1,4200,1,4210,.1));
 CHECK("cov-disabled", coverageAllows(0,1,0));
 CHECK("cov-100", coverageAllows(100,1,1));
 CHECK("cov-equality", coverageAllows(50,2,1));
 CHECK("cov-under", !coverageAllows(60,2,1));
 CHECK("cov-over100exposure", coverageAllows(100,1,1.2));
 CHECK("cov-no-core", !coverageAllows(50,0,1));
 CHECK("corridor-disabled", corridorAllows(0,CORE_BUY,4200,4190,.1));
 CHECK("buy-positive", std::abs(corridorPips(CORE_BUY,4190,4195,.1)-50)<1e-9);
 CHECK("buy-zero", std::abs(corridorPips(CORE_BUY,4195,4195,.1))<1e-9);
 CHECK("buy-negative", corridorPips(CORE_BUY,4200,4195,.1)<0);
 CHECK("sell-positive", std::abs(corridorPips(CORE_SELL,4205,4200,.1)-50)<1e-9);
 CHECK("sell-zero", std::abs(corridorPips(CORE_SELL,4200,4200,.1))<1e-9);
 CHECK("sell-negative", corridorPips(CORE_SELL,4195,4200,.1)<0);
 CHECK("corridor-below-target", corridorAllows(60,CORE_BUY,4190,4195,.1));
 CHECK("corridor-exact-target-block", !corridorAllows(50,CORE_BUY,4190,4195,.1));
 CHECK("corridor-above-block", !corridorAllows(40,CORE_BUY,4190,4195,.1));
 CHECK("negative-corridor-allows", corridorAllows(10,CORE_BUY,4200,4195,.1));
 CHECK("corridor-invalid-pip", !corridorAllows(10,CORE_BUY,4190,4195,0));
 CHECK("combined-coverage-block", !gate(ACTIVE,true,HEDGE_ACTIVE,80,0,CORE_BUY,1,4190,.5,4195,.1));
 CHECK("combined-corridor-block", !gate(ACTIVE,true,HEDGE_ACTIVE,0,50,CORE_BUY,1,4190,1,4195,.1));
 CHECK("combined-pass", gate(ACTIVE,true,HEDGE_ACTIVE,50,60,CORE_BUY,1,4190,.8,4195,.1));
 CHECK("armed-ignores-coverage", gate(ACTIVE,false,ARMED,100,50,CORE_BUY,1,4190,0,0,.1));
 CHECK("armed-ignores-corridor", gate(ACTIVE,false,ARMED,0,1,CORE_BUY,1,4190,0,0,.1));
 std::cout<<passed<<" passed, "<<failed<<" failed\n";
 return failed?1:0;
}
