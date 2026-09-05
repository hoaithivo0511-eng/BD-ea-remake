// Adaptive Recovery Hedge T4 — pure smart-split/lifecycle model tests.
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <string>
#include <vector>
using namespace std;

static int pass_count=0, fail_count=0;
static void Check(const char* n,bool ok){ if(ok){pass_count++;return;} fail_count++; printf("FAIL: %s\n",n); }
static void CheckEq(const char* n,long a,long b){ Check(n,a==b); }
static void CheckNear(const char* n,double a,double b,double e=1e-9){ Check(n,fabs(a-b)<=e); }

static long FloorUnits(double v,double step){ return v>0&&step>0?(long)floor(v/step+1e-9):0; }
static long CeilUnits(double v,double step){ return v>0&&step>0?(long)ceil(v/step-1e-9):0; }
static bool LimitAllows(long target,long existing,long limit){
  if(target<=0||existing<0||limit<0)return false;
  if(limit==0)return true;
  if(existing>limit)return false;
  return target<=limit-existing;
}
static long NextChild(long remaining,long minU,long maxU){
  if(remaining<=0||minU<=0||maxU<minU||remaining<minU)return 0;
  if(remaining<=maxU)return remaining;
  long child=maxU,residual=remaining-child;
  if(residual>0&&residual<minU){
    long shift=minU-residual; child-=shift;
    if(child<minU)return 0;
    residual=remaining-child;
  }
  if(child<minU||child>maxU)return 0;
  if(residual>0&&residual<minU)return 0;
  return child;
}
static bool BuildPlan(long target,long minU,long maxU,long existing,long limit,vector<long>& out){
  out.clear();
  if(target<=0||minU<=0||maxU<minU||!LimitAllows(target,existing,limit))return false;
  long r=target;
  while(r>0){ long c=NextChild(r,minU,maxU); if(c<=0){out.clear();return false;} out.push_back(c); r-=c; }
  long sum=0; for(long c:out){ if(c<minU||c>maxU)return false; sum+=c; }
  return sum==target;
}
static long Rehedge(long core,long hedge){ if(core<=0)return 0; if(hedge<=0)return core; return core>hedge?core-hedge:0; }
static long ConfirmedNew(long active,long baseline){ return active<=baseline?0:active-baseline; }
static double BundleCoverage(long confirmed,long target){ return confirmed<=0||target<=0?0:(double)confirmed/target*100.0; }
static bool CanSubmit(long confirmed,long target,bool inflight,bool recon,bool blocked){
  if(target<=0||confirmed<0||confirmed>=target)return false;
  return !inflight&&!recon&&!blocked;
}

enum State{ ARMED=0,HEDGE_BUILDING,HEDGE_ACTIVE,RECONCILE_REQUIRED };
struct BundleCycle{
  State state=ARMED; int generation=0,bundleId=0,submitted=0;
  long target=0,baseline=0,confirmed=0; bool inflight=false,partial=false,blocked=false,recon=false,complete=false;
};
static bool Begin(BundleCycle& c,long target,long baseline){
  if(c.state!=ARMED||target<=0||baseline<0)return false;
  c.state=HEDGE_BUILDING;c.generation++;c.bundleId++;c.target=target;c.baseline=baseline;
  c.confirmed=0;c.submitted=0;c.inflight=false;c.partial=false;c.blocked=false;c.recon=false;c.complete=false;return true;
}
static bool Submit(BundleCycle& c,long child){
  if(c.state!=HEDGE_BUILDING||!CanSubmit(c.confirmed,c.target,c.inflight,c.recon,c.blocked)||child<=0||child>c.target-c.confirmed)return false;
  c.inflight=true;c.submitted++;return true;
}
static bool Observe(BundleCycle& c,long currentActive,bool pending,bool execRecon){
  if(c.state!=HEDGE_BUILDING||currentActive<0)return false;
  c.inflight=pending;c.confirmed=ConfirmedNew(currentActive,c.baseline);c.partial=c.confirmed>0&&c.confirmed<c.target;
  if(execRecon){c.recon=true;c.state=RECONCILE_REQUIRED;return false;}
  if(c.confirmed>c.target){c.recon=true;c.state=RECONCILE_REQUIRED;return false;}
  if(c.confirmed==c.target&&!pending){c.complete=true;c.partial=false;c.state=HEDGE_ACTIVE;return true;}
  return true;
}

int main(){
  // Unit conversion: min uses ceil, target/max/limit use floor.
  CheckEq("floor exact",FloorUnits(12.37,0.01),1237);
  CheckEq("floor never up",FloorUnits(0.245,0.01),24);
  CheckEq("ceil exact",CeilUnits(0.10,0.01),10);
  CheckEq("ceil min never down",CeilUnits(0.015,0.01),2);

  vector<long> p;
  Check("below max one child",BuildPlan(237,1,500,0,0,p)&&p.size()==1&&p[0]==237);
  Check("exact max one child",BuildPlan(500,1,500,0,0,p)&&p.size()==1&&p[0]==500);
  Check("max plus step two",BuildPlan(501,1,500,0,0,p)&&p.size()==2&&p[0]==500&&p[1]==1);
  Check("12.37 split 5/5/2.37",BuildPlan(1237,1,500,0,0,p)&&p.size()==3&&p[0]==500&&p[1]==500&&p[2]==237);
  Check("residual redistributed to min",BuildPlan(501,10,500,0,0,p)&&p.size()==2&&p[0]==491&&p[1]==10);
  Check("residual 9 redistributed",BuildPlan(509,10,500,0,0,p)&&p.size()==2&&p[0]==499&&p[1]==10);
  Check("exact 20 as 10+10",BuildPlan(20,10,15,0,0,p)&&p.size()==2&&p[0]==10&&p[1]==10);
  Check("target below min impossible",!BuildPlan(9,10,500,0,0,p));
  Check("16 impossible with min10 max15",!BuildPlan(16,10,15,0,0,p));
  Check("zero target invalid",!BuildPlan(0,1,500,0,0,p));

  Check("unlimited volume limit",LimitAllows(9999,9000,0));
  Check("limit exact allowed",LimitAllows(300,700,1000));
  Check("limit exceed blocked",!LimitAllows(301,700,1000));
  Check("existing over limit blocked",!LimitAllows(1,1001,1000));
  Check("plan obeys limit",BuildPlan(300,1,500,700,1000,p));
  Check("plan rejects aggregate limit",!BuildPlan(301,1,500,700,1000,p));

  long sum=0; BuildPlan(1237,1,500,0,0,p); for(long c:p)sum+=c;
  CheckEq("plan exact no under hedge",sum,1237);
  Check("all children <= broker max",all_of(p.begin(),p.end(),[](long x){return x<=500;}));
  Check("all children >= broker min",all_of(p.begin(),p.end(),[](long x){return x>=1;}));

  CheckEq("initial required 1to1",Rehedge(130,0),130);
  CheckEq("rehedge deficit",Rehedge(130,50),80);
  CheckEq("rehedge fully covered",Rehedge(130,130),0);
  CheckEq("rehedge overcovered zero",Rehedge(100,120),0);
  CheckEq("no core no rehedge",Rehedge(0,50),0);

  CheckEq("confirmed baseline zero",ConfirmedNew(50,50),0);
  CheckEq("confirmed delta",ConfirmedNew(80,50),30);
  CheckNear("bundle coverage partial",BundleCoverage(30,80),37.5);
  CheckNear("bundle coverage complete",BundleCoverage(80,80),100.0);
  CheckNear("bundle coverage no fill",BundleCoverage(0,80),0.0);

  Check("can submit clean",CanSubmit(0,100,false,false,false));
  Check("no second child inflight",!CanSubmit(0,100,true,false,false));
  Check("no submit reconcile",!CanSubmit(0,100,false,true,false));
  Check("no submit after explicit reject",!CanSubmit(0,100,false,false,true));
  Check("no submit complete",!CanSubmit(100,100,false,false,false));

  BundleCycle buy,sell;
  Check("begin logical bundle",Begin(buy,1237,0));
  CheckEq("generation increments once",buy.generation,1);
  CheckEq("bundle id increments once",buy.bundleId,1);
  Check("submit child1",Submit(buy,500));
  CheckEq("child does not increment generation",buy.generation,1);
  Check("cannot submit child2 while inflight",!Submit(buy,500));
  Check("partial fill observed",Observe(buy,300,false,false)&&buy.confirmed==300&&buy.partial);
  Check("can submit after confirmed partial",CanSubmit(buy.confirmed,buy.target,buy.inflight,buy.recon,buy.blocked));
  Check("submit child2 after reconciliation",Submit(buy,500));
  CheckEq("still one logical generation",buy.generation,1);
  Check("target confirm activates",Observe(buy,1237,false,false)&&buy.state==HEDGE_ACTIVE&&buy.complete);

  BundleCycle over;
  Begin(over,100,20);
  Check("overfill fails closed",!Observe(over,121,false,false)&&over.state==RECONCILE_REQUIRED&&over.recon);

  BundleCycle uncertain;
  Begin(uncertain,100,0); Submit(uncertain,50);
  Check("execution reconcile fails closed",!Observe(uncertain,0,true,true)&&uncertain.state==RECONCILE_REQUIRED);

  CheckEq("partial fill impossible residual detected",NextChild(9,10,500),0);
  CheckEq("partial fill legal residual",NextChild(15,10,500),15);

  Check("parallel sell cycle independent",Begin(sell,200,0)&&sell.generation==1&&buy.generation==1);
  Check("sell inflight does not alter buy",Submit(sell,100)&&buy.state==HEDGE_ACTIVE&&buy.complete);

  printf("Recovery T4 bundle suite: %d passed, %d failed\n",pass_count,fail_count);
  return fail_count==0?0:1;
}
