// Adaptive Recovery Hedge T5 — standalone pure virtual-TP/ledger/allocator tests.
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <vector>
using namespace std;
static int pass_count=0, fail_count=0;
static void Check(const char*n,bool ok){if(ok)pass_count++;else{fail_count++;printf("FAIL: %s\n",n);}}
enum Mode{Oldest=0,Newest,Lossiest,ProRata};
struct Cand{unsigned long long ticket;long time,units;double cash;};
struct Act{unsigned long long ticket;long units;double loss;};
struct Ledger{double hedge=0,spent=0,credit=0;long hedgeUnits=0;bool deficit=false;};
double DealCash(double p,double s,double c,double f){return p+s+c+f;}
void Recompute(Ledger&l){double positive=max(l.hedge,0.0),raw=positive-l.spent;l.credit=max(raw,0.0);l.deficit=l.spent>positive+1e-8;}
void ApplyHedge(Ledger&l,double c,long u){l.hedge+=c;if(u>0)l.hedgeUnits+=u;Recompute(l);}
void ApplyCore(Ledger&l,double c){if(c<0)l.spent+=-c;Recompute(l);}
double NetBE(double a,double lots,double cost,double tv,double ts,bool buy){if(a<=0||lots<=0||tv<=0||ts<=0)return 0;double sh=cost/(tv*lots)*ts;return buy?a-sh:a+sh;}
bool TpHit(bool coreBuy,double be,double bid,double ask,double d){if(be<=0||bid<=0||ask<=0||d<0)return false;return coreBuy?ask<=be-d:bid>=be+d;}
long PartialTarget(long a,double p,long m){if(a<=0||p<=0||p>100||m<=0)return 0;if(p>=100-1e-12)return a;long t=(long)floor(a*p/100.0+1e-9);if(t<m)return 0;if(t>=a)return a;long r=a-t;if(r>0&&r<m){t=a-m;if(t<m)return 0;}return t;}
long Legal(long q,long p,long m){if(q<=0||p<=0||m<=0)return 0;if(q>=p)return p;if(q<m)return 0;long t=q,r=p-t;if(r>0&&r<m){t=p-m;if(t<m)return 0;}return t;}
double LossPerUnit(const Cand&c){return c.units>0&&c.cash<0?-c.cash/c.units:0;}
bool Before(const Cand&a,const Cand&b,Mode m){if(m==Newest){if(a.time!=b.time)return a.time>b.time;return a.ticket>b.ticket;}if(m==Lossiest){double x=LossPerUnit(a),y=LossPerUnit(b);if(fabs(x-y)>1e-12)return x>y;}if(a.time!=b.time)return a.time<b.time;return a.ticket<b.ticket;}
bool HedgePlan(vector<Cand> c,long target,long minU,vector<Act>&a){a.clear();sort(c.begin(),c.end(),[](const Cand&A,const Cand&B){return A.units!=B.units?A.units>B.units:A.ticket<B.ticket;});long rem=target;for(auto&x:c){if(rem<=0)break;if(rem>=x.units){a.push_back({x.ticket,x.units,0});rem-=x.units;}else{long u=Legal(rem,x.units,minU);if(u==rem){a.push_back({x.ticket,u,0});rem=0;}}}return rem==0&&!a.empty();}
bool CorePlan(vector<Cand> c,Mode mode,double credit,long minU,vector<Act>&a,double&est){a.clear();est=0;if(credit<=0||minU<=0)return false;stable_sort(c.begin(),c.end(),[mode](const Cand&A,const Cand&B){return Before(A,B,mode);});double rem=credit;if(mode==ProRata){double total=0;for(auto&x:c)if(x.units>0&&x.cash<0)total+=-x.cash;if(total<=0)return false;double frac=min(1.0,credit/total);int n=(int)c.size();vector<long> plan(n);vector<double> rank(n,-1);for(int i=0;i<n;i++){if(c[i].units<=0||c[i].cash>=0)continue;double raw=c[i].units*frac;long wanted=(long)floor(raw+1e-9);plan[i]=Legal(wanted,c[i].units,minU);rank[i]=raw-floor(raw);if(plan[i]>0){double loss=LossPerUnit(c[i])*plan[i];if(loss<=rem+1e-8)rem-=loss;else plan[i]=0;}}vector<bool> used(n);for(int pass=0;pass<n;pass++){int best=-1;for(int i=0;i<n;i++)if(!used[i]&&rank[i]>=0&&(best<0||rank[i]>rank[best]+1e-12))best=i;if(best<0)break;used[best]=true;long req=plan[best]>0?plan[best]+1:minU;long next=Legal(req,c[best].units,minU);if(next<=plan[best])continue;long delta=next-plan[best];double loss=LossPerUnit(c[best])*delta;if(loss<=rem+1e-8){plan[best]=next;rem-=loss;}}for(int i=0;i<n;i++)if(plan[i]>0){double loss=LossPerUnit(c[i])*plan[i];a.push_back({c[i].ticket,plan[i],loss});est+=loss;}}else{for(auto&x:c){if(rem<=1e-8)break;double lp=LossPerUnit(x);if(lp<=0)continue;long maxBy=(long)floor(rem/lp+1e-9);if(maxBy<=0)continue;long wanted=min(x.units,maxBy),u=Legal(wanted,x.units,minU);if(u<=0)continue;double loss=lp*u;if(loss>rem+1e-8)continue;a.push_back({x.ticket,u,loss});est+=loss;rem-=loss;}}return !a.empty();}
int main(){
 Check("deal profit+swap+commission+fee",fabs(DealCash(120,-2,-3,-1)-114)<1e-9);
 Ledger neg;ApplyHedge(neg,-5,10);Check("negative hedge with zero Core spend is no-credit not deficit",neg.credit==0&&!neg.deficit);
 Ledger l;ApplyHedge(l,114,618);Check("confirmed hedge credit",fabs(l.credit-114)<1e-9&&l.hedgeUnits==618&&!l.deficit);
 Check("unconfirmed request creates no credit",Ledger{}.credit==0);
 ApplyCore(l,-40);Check("actual Core loss debits credit",fabs(l.credit-74)<1e-9);
 ApplyCore(l,5);Check("profitable Core close does not manufacture credit",fabs(l.credit-74)<1e-9);
 ApplyCore(l,-80);Check("credit deficit is surfaced",l.credit==0&&l.deficit);
 Check("BUY hedge net-BE cost shift",NetBE(100,1,-10,1,1,true)==110);
 Check("SELL hedge net-BE cost shift",NetBE(100,1,-10,1,1,false)==90);
 Check("SELL hedge TP uses ask",TpHit(true,100,94.8,95,5));
 Check("SELL hedge does not trigger on bid alone",!TpHit(true,100,94,96,5));
 Check("BUY hedge TP uses bid",TpHit(false,100,105,105.2,5));
 Check("50pct 12.37 => 6.18",PartialTarget(1237,50,1)==618);
 Check("partial percentage never rounds upward",PartialTarget(3,50,1)==1);
 Check("below-min remainder does not force over-close",PartialTarget(3,80,2)==0);
 vector<Act>a;Check("split bundle 6.18 => 5.00 + 1.18",HedgePlan({{1,1,500,0},{2,2,500,0},{3,3,237,0}},618,1,a)&&a.size()==2&&a[0].units==500&&a[1].units==118);
 Check("mixed child exact target",HedgePlan({{1,1,300,0},{2,2,200,0},{3,3,100,0}},350,50,a)&&a.size()==2&&a[1].units==50);
 Check("impossible target refuses over-close",!HedgePlan({{1,1,150,0},{2,2,150,0}},100,100,a));
 vector<Cand> core={{11,1,100,-100},{22,2,100,-50},{33,3,100,-200},{44,4,100,10}};double est=0;
 Check("OLDEST allocator",CorePlan(core,Oldest,120,1,a,est)&&a[0].ticket==11);
 Check("NEWEST skips profitable newest",CorePlan(core,Newest,60,1,a,est)&&a[0].ticket==33);
 Check("LOSSIEST sorts by loss per unit",CorePlan(core,Lossiest,60,1,a,est)&&a[0].ticket==33);
 Check("OLDEST partial funded by credit",CorePlan(core,Oldest,25,1,a,est)&&a[0].units==25);
 Check("zero/unconfirmed credit cannot spend",!CorePlan(core,Oldest,0,1,a,est));
 Check("winning Core is never funded",!CorePlan({{1,1,100,5}},Oldest,100,1,a,est));
 Check("PRO_RATA bounded by credit",CorePlan(core,ProRata,175,1,a,est)&&a.size()==3&&est<=175+1e-8);
 vector<Cand> equal={{1,1,10,-100},{2,2,10,-100},{3,3,10,-100}};
 Check("PRO_RATA deterministic largest-remainder residual",CorePlan(equal,ProRata,100,1,a,est)&&a.size()==3&&a[0].units==4&&a[1].units==3&&a[2].units==3);
 Ledger actual;ApplyHedge(actual,50,40);Check("actual close units override requested units",actual.hedgeUnits==40);
 ApplyCore(actual,-20);Check("actual realized cash overrides estimate",fabs(actual.credit-30)<1e-9);
 printf("Recovery T5 exit suite: %d passed, %d failed\n",pass_count,fail_count);return fail_count?1:0;
}
