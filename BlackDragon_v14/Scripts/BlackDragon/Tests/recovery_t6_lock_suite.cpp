// Adaptive Recovery Hedge T6 — standalone pure lock/re-hedge tests.
#include <algorithm>
#include <cmath>
#include <cstdio>
using namespace std;
static int pass_count=0, fail_count=0;
static void Check(const char*n,bool ok){if(ok){pass_count++;}else{fail_count++;printf("FAIL: %s\n",n);}}
enum Dir{CORE_BUY=0,CORE_SELL=1};
static double Norm(Dir d,double price,double tick){if(price<=0||tick<=0)return 0;double q=price/tick;double k=d==CORE_BUY?floor(q+1e-9):ceil(q-1e-9);return k*tick;}
static double Target(Dir d,double entry,double be,double profit,double safety,double tick){if(entry<=0||be<=0||profit<0||safety<=0||tick<=0)return 0;double raw=d==CORE_BUY?min(entry-profit,be-safety):max(entry+profit,be+safety);double p=Norm(d,raw,tick);if(d==CORE_BUY){if(!(p<be-1e-9))return 0;}else if(!(p>be+1e-9))return 0;return p;}
static bool Satisfied(Dir d,double sl,double target,double tick){if(sl<=0||target<=0)return false;double e=tick>0?tick*0.5:1e-9;return d==CORE_BUY?sl<=target+e:sl>=target-e;}
static bool BrokerValid(Dir d,double target,double bid,double ask,double point,int stops,int freeze,double tick){if(target<=0||bid<=0||ask<=0||point<=0||tick<=0)return false;double dist=max(stops,freeze)*point;double e=tick*0.5;return d==CORE_BUY?target+e>=ask+dist:target-e<=bid-dist;}
static bool GenCanStart(int current,int maxg){return current>=0&&maxg>=1&&current<maxg;}
static bool GapHit(Dir d,long anchor,long bid,long ask,long gap){if(anchor<=0||bid<=0||ask<=0||gap<0)return false;if(gap==0)return true;return d==CORE_BUY?bid<=anchor-gap:ask>=anchor+gap;}
static long Rehedge(long core,long hedge){return core>hedge?core-hedge:0;}
static long AnchorTicks(double weighted,long units,double tick){if(weighted<=0||units<=0||tick<=0)return 0;return lround((weighted/units)/tick);}
int main(){
 Check("SELL lock baseline",fabs(Target(CORE_BUY,100,99.8,.3,.1,.01)-99.7)<1e-9);
 Check("SELL lock BE safety dominates",fabs(Target(CORE_BUY,100,99.6,.3,.1,.01)-99.5)<1e-9);
 Check("BUY lock baseline",fabs(Target(CORE_SELL,100,100.2,.3,.1,.01)-100.3)<1e-9);
 Check("BUY lock BE safety dominates",fabs(Target(CORE_SELL,100,100.4,.3,.1,.01)-100.5)<1e-9);
 Check("SELL tick rounds toward stronger",fabs(Norm(CORE_BUY,99.73,.05)-99.70)<1e-9);
 Check("BUY tick rounds toward stronger",fabs(Norm(CORE_SELL,100.22,.05)-100.25)<1e-9);
 Check("safety buffer mandatory",Target(CORE_BUY,100,99.9,.3,0,.01)==0);
 Check("SELL existing stronger accepted",Satisfied(CORE_BUY,99.5,99.7,.01));
 Check("SELL existing equal accepted",Satisfied(CORE_BUY,99.7,99.7,.01));
 Check("SELL weaker rejected",!Satisfied(CORE_BUY,99.9,99.7,.01));
 Check("BUY existing stronger accepted",Satisfied(CORE_SELL,100.5,100.3,.01));
 Check("BUY weaker rejected",!Satisfied(CORE_SELL,100.1,100.3,.01));
 Check("SELL stops valid",BrokerValid(CORE_BUY,99.7,99.0,99.1,.01,20,10,.01));
 Check("SELL stops invalid near ask",!BrokerValid(CORE_BUY,99.25,99.0,99.1,.01,20,10,.01));
 Check("SELL freeze dominates",!BrokerValid(CORE_BUY,99.45,99.0,99.1,.01,10,40,.01));
 Check("BUY stops valid",BrokerValid(CORE_SELL,100.3,100.9,101.0,.01,20,10,.01));
 Check("BUY stops invalid near bid",!BrokerValid(CORE_SELL,100.75,100.9,101.0,.01,20,10,.01));
 Check("BUY freeze dominates",!BrokerValid(CORE_SELL,100.55,100.9,101.0,.01,10,40,.01));
 Check("generation 1 allowed from zero",GenCanStart(0,1));
 Check("generation Max+1 blocked",!GenCanStart(1,1));
 Check("generation 5 allowed from four",GenCanStart(4,5));
 Check("generation six blocked at five",!GenCanStart(5,5));
 Check("bad max blocked",!GenCanStart(0,0));
 Check("BUY core rehedge adverse gap",GapHit(CORE_BUY,1000,950,960,50));
 Check("BUY core rehedge not early",!GapHit(CORE_BUY,1000,951,960,50));
 Check("SELL core rehedge adverse gap",GapHit(CORE_SELL,1000,1040,1050,50));
 Check("SELL core rehedge not early",!GapHit(CORE_SELL,1000,1040,1049,50));
 Check("zero gap immediate",GapHit(CORE_BUY,1000,1000,1001,0));
 Check("rehedge deficit zero",Rehedge(50,50)==0);
 Check("rehedge deficit partial",Rehedge(130,50)==80);
 Check("rehedge deficit full",Rehedge(130,0)==130);
 Check("overhedged never negative",Rehedge(50,80)==0);
 Check("weighted actual anchor",AnchorTicks(100.0*50+101.0*50,100,.1)==1005);
 Check("anchor invalid without units",AnchorTicks(100,0,.1)==0);
 printf("Recovery T6 lock suite: %d passed, %d failed\n",pass_count,fail_count);
 return fail_count==0?0:1;
}
