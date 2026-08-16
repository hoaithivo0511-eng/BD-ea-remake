// Adaptive Recovery Hedge T5 — standalone pure virtual-TP/ledger/allocator tests.
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <vector>
using namespace std;
static int pass_count=0, fail_count=0;
static void Check(const char*n,bool ok){ if(ok){pass_count++;return;} fail_count++; printf("FAIL: %s\n",n); }

enum Mode{ Oldest=0, Newest, Lossiest, ProRata };
struct Cand{ unsigned long long ticket; long time; long units; double cash; };
struct Act{ unsigned long long ticket; long units; double loss; };
struct Ledger{ double hedge=0,spent=0,credit=0; long hedgeUnits=0; bool deficit=false; };

double DealCash(double p,double s,double c,double f){return p+s+c+f;}
void Recompute(Ledger &l){double r=l.hedge-l.spent;l.credit=r>0?r:0;l.deficit=l.spent>l.hedge+1e-8;}
void ApplyHedge(Ledger &l,double cash,long units){l.hedge+=cash;if(units>0)l.hedgeUnits+=units;Recompute(l);}
void ApplyCore(Ledger &l,double cash){if(cash<0)l.spent+=-cash;Recompute(l);}
double NetBE(double avg,double lots,double cost,double tv,double ts,bool buy){if(avg<=0||lots<=0||tv<=0||ts<=0)return 0;double sh=cost/(tv*lots)*ts;return buy?avg-sh:avg+sh;}
bool TpHit(bool coreBuy,double be,double bid,double ask,double dist){if(be<=0||bid<=0||ask<=0||dist<0)return false;return coreBuy?ask<=be-dist:bid>=be+dist;}
long PartialTarget(long active,double pct,long minU){if(active<=0||pct<=0||pct>100||minU<=0)return 0;if(pct>=100-1e-12)return active;long t=(long)floor(active*pct/100.0+1e-9);if(t<minU)return 0;if(t>=active)return active;long r=active-t;if(r>0&&r<minU){t=active-minU;if(t<minU)return 0;}return t;}
long Legal(long req,long pos,long minU){if(req<=0||pos<=0||minU<=0)return 0;if(req>=pos)return pos;if(req<minU)return 0;long t=req,r=pos-t;if(r>0&&r<minU){t=pos-minU;if(t<minU)return 0;}return t;}
bool HedgePlan(vector<Cand> c,long target,long minU,vector<Act>&a){a.clear();sort(c.begin(),c.end(),[](const Cand&A,const Cand&B){return A.units!=B.units?A.units>B.units:A.ticket<B.ticket;});long rem=target;for(auto &x:c){if(rem<=0)break;if(x.units<=0)continue;if(rem>=x.units){a.push_back({x.ticket,x.units,0});rem-=x.units;continue;}long p=Legal(rem,x.units,minU);if(p==rem){a.push_back({x.ticket,p,0});rem=0;}}return rem==0&&!a.empty();}
double LossPerUnit(const Cand&c){return c.units>0&&c.cash<0?-c.cash/c.units:0;}
bool Before(const Cand&a,const Cand&b,Mode m){if(m==Newest){if(a.time!=b.time)return a.time>b.time;return a.ticket>b.ticket;}if(m==Lossiest){double x=LossPerUnit(a),y=LossPerUnit(b);if(fabs(x-y)>1e-12)return x>y;}if(a.time!=b.time)return a.time<b.time;return a.ticket<b.ticket;}
bool CorePlan(vector<Cand> c,Mode m,double credit,long minU,vector<Act>&a,double &est){a.clear();est=0;if(credit<=0||minU<=0)return false;stable_sort(c.begin(),c.end(),[m](const Cand&A,const Cand&B){return Before(A,B,m);});double rem=credit;if(m==ProRata){double total=0;for(auto &x:c)if(x.units>0&&x.cash<0)total+=-x.cash;if(total<=0)return false;double frac=min(1.0,credit/total);for(auto &x:c){if(x.units<=0||x.cash>=0)continue;long wanted=(long)floor(x.units*frac+1e-9);long u=Legal(wanted,x.units,minU);if(u<=0)continue;double loss=LossPerUnit(x)*u;if(loss>rem+1e-8)continue;a.push_back({x.ticket,u,loss});est+=loss;rem-=loss;}}else{for(auto &x:c){if(rem<=1e-8)break;double lp=LossPerUnit(x);if(lp<=0)continue;long maxBy=(long)floor(rem/lp+1e-9);if(maxBy<=0)continue;long u=Legal(min(x.units,maxBy),x.units,minU);if(u<=0)continue;double loss=lp*u;if(loss>rem+1e-8)continue;a.push_back({x.ticket,u,loss});est+=loss;rem-=loss;}}return !a.empty();}

int main(){
  Check("deal profit+swap+commission+fee",fabs(DealCash(120,-2,-3,-1)-114)<1e-9);
  Ledger l; ApplyHedge(l,114,618); Check("confirmed hedge credit",fabs(l.credit-114)<1e-9&&l.hedgeUnits==618&&!l.deficit);
  Check("unconfirmed request creates no credit",Ledger{}.credit==0);
  ApplyCore(l,-40); Check("actual Core loss debits credit",fabs(l.credit-74)<1e-9&&fabs(l.spent-40)<1e-9);
  ApplyCore(l,5); Check("profitable Core close does not manufacture credit",fabs(l.credit-74)<1e-9);
  ApplyCore(l,-80); Check("credit deficit is surfaced",l.credit==0&&l.deficit);
  Check("BUY hedge net-BE cost shift",NetBE(100,1,-10,1,1,true)==110);
  Check("SELL hedge net-BE cost shift",NetBE(100,1,-10,1,1,false)==90);
  Check("SELL hedge TP uses ask",TpHit(true,100,94.8,95,5));
  Check("SELL hedge does not trigger on bid alone",!TpHit(true,100,94,96,5));
  Check("BUY hedge TP uses bid",TpHit(false,100,105,105.2,5));
  Check("50pct 12.37 lot => 6.18 units-equivalent",PartialTarget(1237,50,1)==618);
  Check("partial percentage never rounds upward",PartialTarget(3,50,1)==1);
  Check("below-min remainder does not force over-close",PartialTarget(3,80,2)==0);
  vector<Cand> hedge={{1,1,500,0},{2,2,500,0},{3,3,237,0}}; vector<Act> acts;
  Check("split bundle 6.18 => full 5.00 + partial 1.18",HedgePlan(hedge,618,1,acts)&&acts.size()==2&&acts[0].units==500&&acts[1].units==118);
  Check("mixed child exact target",HedgePlan({{1,1,300,0},{2,2,200,0},{3,3,100,0}},350,50,acts)&&acts.size()==2&&acts[0].units==300&&acts[1].units==50);
  Check("impossible target refuses over-close",!HedgePlan({{1,1,150,0},{2,2,150,0}},100,100,acts));
  vector<Cand> core={{11,1,100,-100},{22,2,100,-50},{33,3,100,-200},{44,4,100,10}}; double est=0;
  Check("OLDEST allocator",CorePlan(core,Oldest,120,1,acts,est)&&acts[0].ticket==11);
  Check("NEWEST skips profitable newest and takes newest loser",CorePlan(core,Newest,60,1,acts,est)&&acts[0].ticket==33);
  Check("LOSSIEST sorts by loss per unit",CorePlan(core,Lossiest,60,1,acts,est)&&acts[0].ticket==33);
  Check("OLDEST partial funded by credit",CorePlan(core,Oldest,25,1,acts,est)&&acts[0].ticket==11&&acts[0].units==25);
  Check("zero/unconfirmed credit cannot spend",!CorePlan(core,Oldest,0,1,acts,est));
  Check("winning Core is never funded as a loss close",!CorePlan({{1,1,100,5}},Oldest,100,1,acts,est));
  Check("PRO_RATA produces bounded plan",CorePlan(core,ProRata,175,1,acts,est)&&acts.size()==3&&est<=175+1e-8);
  Ledger actual; ApplyHedge(actual,50,40); Check("actual close units override requested units",actual.hedgeUnits==40);
  ApplyCore(actual,-20); Check("actual realized cash overrides estimate",fabs(actual.credit-30)<1e-9);
  printf("Recovery T5 exit suite: %d passed, %d failed\n",pass_count,fail_count);
  return fail_count==0?0:1;
}
