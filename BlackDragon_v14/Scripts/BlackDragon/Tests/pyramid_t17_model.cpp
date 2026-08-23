#include <cmath>
#include <iostream>
#include <string>
#include <algorithm>
#include <vector>

static int pass_count=0, fail_count=0;
static void check(const std::string& n,bool ok){if(ok)++pass_count;else{++fail_count;std::cout<<"FAIL: "<<n<<"\n";}}
static bool favorable(int d,double anchor,double bid,double ask,double gap){return anchor>0&&bid>0&&ask>0&&gap>=0&&(d==0?ask>=anchor+gap:bid<=anchor-gap);} 
static bool peel(int d,double open,double bid,double ask,double gap){return open>0&&bid>0&&ask>0&&gap>=0&&(d==0?bid<=open-gap:ask>=open+gap);} 
static double favp(int d,double be,double bid,double ask,double p){if(be<=0||p<=0)return 0;double x=d==0?bid:ask;return(d==0?x-be:be-x)/p;}
static double room(int d,double tp,double bid,double ask,double p){if(tp<=0||p<=0)return 1e300;return(d==0?tp-ask:bid-tp)/p;}
static double avail(double f,double r,double open,double pct){if(pct<=0)return 0;pct=std::min(pct,100.0);double e=f+r;if(e<=0)return 0;return std::max(e*pct/100.0-std::max(open,0.0),0.0);} 
static int next_serial(int highest){return highest<1?1:highest+1;}
static bool concurrent_allowed(int open,int cap){return cap>0&&open>=0&&open<cap;}
static double base_anchor(double newest,double be){return newest>0?newest:be;}
static double rearm_anchor(double newest,double be,long newestNon,long lastAdd,long lastExit,double exitPx){
  if(newestNon>lastAdd && be>0) return be;
  if(lastExit>lastAdd && exitPx>0) return exitPx;
  return base_anchor(newest,be);
}
static bool old_timing(long last,long lastbar,long now,long bar,int mins){if(lastbar==bar&&bar>0)return false;if(mins>0&&last>0&&now<=last+(long)mins*60)return false;return true;}
static bool mutation_timing(long lastMutation,long now,long bar,int mins){if(bar>0&&lastMutation>=bar)return false;if(mins>0&&lastMutation>0&&now<=lastMutation+(long)mins*60)return false;return true;}
static bool risk_applies(int mode,double pct){return mode!=0&&pct>0;}
static bool risk_mode_ready(int mode,double pct){return mode!=2||pct>0;}
static double econ(double f,double r){return f+r;}
static double pips_cash(double pips,double lots,double tv,double ts,double pip){if(pips<=0||lots<=0||tv<=0||ts<=0||pip<=0)return 0;return pips*pip/ts*tv*lots;}
static bool economic_lock(double f,double r,double minPips,double lots,double tv,double ts,double pip){if(minPips<=0)return true;double need=pips_cash(minPips,lots,tv,ts,pip);return need>0&&econ(f,r)+1e-9>=need;}
static bool fixed_peel_reserve(double f,double livePyr,double r,double lock,double openRisk,double candidateRisk){if(lock<0||openRisk<0||candidateRisk<=0)return false;return f-livePyr+r+1e-9>=lock+openRisk+candidateRisk;}
static bool dca_release(bool due,int total,int maxOrders,int pyramids){return due&&maxOrders>0&&total>=maxOrders&&pyramids>0;}
static int active_campaign_start(const std::vector<long>& deltas,long current){if(current<=0)return-1;long units=current;for(int i=(int)deltas.size()-1;i>=0;--i){long previous=units-deltas[(size_t)i];if(previous<0)return-1;if(deltas[(size_t)i]>0&&previous==0)return i;units=previous;}return-1;}
static double shift(double r,double lots,double tv,double ts){if(r>=0||lots<=0||tv<=0||ts<=0)return 0;return(-r)/(tv*lots)*ts;}
static double adjtp(int d,double base,double r,double lots,double tv,double ts){double s=shift(r,lots,tv,ts);return d==0?base+s:base-s;}
static double cov(double s,double master,double hard){double v=s;if(master>0&&v>master)v=master;if(hard>0&&v>hard)v=hard;return v>0?v:0;}
static std::vector<double> normalize_cov(std::vector<double> raw,double master,double hard){
 std::vector<double> out;
 for(double v:raw){v=cov(v,master,hard);if(v>0)out.push_back(v);}
 std::sort(out.begin(),out.end());
 out.erase(std::unique(out.begin(),out.end(),[](double a,double b){return std::fabs(a-b)<=1e-9;}),out.end());
 double final_cap=cov(master,master,hard);
 if(final_cap>0&&(out.empty()||final_cap>out.back()+1e-9))out.push_back(final_cap);
 return out;
}
static long pct_units(long core,double p){return core>0&&p>0?(long)std::floor(core*p/100.0+1e-9):0;}
static long rawgen(int policy,long core,long existing,double p){long d=pct_units(core,p);if(d<=0)return 0;if(policy==1)return d;existing=std::max(existing,0L);return d>existing?d-existing:0;}
static long clampmin(long x,long m){if(x<=0)return 0;if(m<=0)return x;return x<m?m:x;}
static bool money_tp(double p,double tp){return tp>0&&p>=tp;}
static bool pctdiff(double buy,double sell,double pct){if(pct<=0)return false;double win=std::max(buy,sell),lose=std::min(buy,sell);if(lose>=0)return false;return win+lose*(1.0+pct/100.0)>=0;}
static bool pctdiff_buffered(double buy,double sell,double pct,double buffer){return pctdiff(buy,sell,pct)&&(buy+sell)>=std::max(buffer,0.0);}
static bool pctdiff_economic_buffered(double buy,double sell,double pct,double realized,bool valid,double buffer){return valid&&pctdiff(buy,sell,pct)&&(buy+sell+realized)>=std::max(buffer,0.0);}
static double execution_reserve(double spread,double deviation,double lots,int requests,double ts,double tv){if(ts<=0||tv<=0)return 1e300;if(lots<=0)return 0;int n=std::max(requests,1);double move=2.0*std::max(spread,ts)+std::max(deviation,0.0)*n;return move/ts*tv*lots;}
static bool overlap_safe(double first,double last,double reserve){return reserve<1e299&&first+last+1e-9>=std::max(reserve,0.0);}
enum GuardAction{NONE=0,ACCOUNT=1,MAGIC=2,BUY=3,SELL=4,DAILY=5};
static int latch_next(int latched,int triggered,bool flat){if(latched!=NONE)return flat?NONE:latched;return triggered;}

int main(){
 check("BUY favorable",favorable(0,4000,4000.9,4001,1)); check("SELL favorable",favorable(1,4000,3999,3999.1,1));
 check("BUY peel",peel(0,4001,4000.3,4000.4,0.7)); check("SELL peel",peel(1,3999,3999.6,3999.7,0.7));
 check("BUY favorable pips",std::fabs(favp(0,4000,4001,4001.1,0.1)-10)<1e-9); check("room TP",std::fabs(room(0,4002,4001.4,4001.5,0.1)-5)<1e-9);
 check("serial first",next_serial(0)==1); check("serial exceeds old 32",next_serial(32)==33); check("serial 100",next_serial(100)==101);
 check("concurrent 2/3 allowed",concurrent_allowed(2,3)); check("concurrent 3/3 blocked",!concurrent_allowed(3,3)); check("zero cap blocks",!concurrent_allowed(0,0)); check("30 historical irrelevant",concurrent_allowed(0,3));
 check("base anchor live",std::fabs(base_anchor(4020,3990)-4020)<1e-9); check("base anchor BE",std::fabs(base_anchor(0,3990)-3990)<1e-9);
 check("post-peel anchor is exit not historical extreme",std::fabs(rearm_anchor(4020,3990,90,100,120,4030)-4030)<1e-9);
 check("post-DCA epoch anchor is current BE",std::fabs(rearm_anchor(4020,3988,140,100,120,4030)-3988)<1e-9);
 check("normal live anchor after new add",std::fabs(rearm_anchor(4040,3990,90,150,120,4030)-4040)<1e-9);
 check("old same bar blocked",!old_timing(100,100,110,100,0)); check("old new bar allowed",old_timing(100,100,160,120,0));
 check("Peel mutation blocks refill same bar",!mutation_timing(130,150,120,0));
 check("later bar allows when delay off",mutation_timing(130,181,180,0));
 check("later bar MinuteStop still blocks",!mutation_timing(130,200,180,5));
 check("later bar MinuteStop passes",mutation_timing(130,431,420,5));
 check("fixed ignores risk",!risk_applies(0,30)); check("multiplier risk on",risk_applies(1,30)); check("multiplier risk zero off",!risk_applies(1,0)); check("risk mode zero fail closed",!risk_mode_ready(2,0));
 check("economic realized loss",std::fabs(econ(100,-40)-60)<1e-12); check("available risk loss",std::fabs(avail(100,-50,0,100)-50)<1e-12); check("available risk open",std::fabs(avail(100,0,20,30)-10)<1e-12);
 check("economic min lock blocks hidden loss",!economic_lock(20,-80,5,.10,1,.01,.1));
 check("economic min lock allows funded campaign",economic_lock(100,-40,5,.10,1,.01,.1));
 check("zero min lock disabled",economic_lock(-100,-100,0,.10,1,.01,.1));
 check("fixed candidate Peel risk blocks underfunded add",!fixed_peel_reserve(31.99,0,0,2,0,30));
 check("fixed live Pyramid profit is not double-funded",!fixed_peel_reserve(79.99,30,0,2,18,30));
 check("fixed full residual Peel reserve exact boundary allows",fixed_peel_reserve(80,30,0,2,18,30));
 check("fixed zero min lock still funds Peel risk",!fixed_peel_reserve(29.99,0,0,0,0,30));
 check("fixed realized Peel debt blocks refill",!fixed_peel_reserve(50,0,-25,0,0,30));
 check("DCA priority release when full of Pyramid",dca_release(true,59,59,30));
 check("DCA no release when slot exists",!dca_release(true,58,59,30));
 check("DCA no release when no Pyramid",!dca_release(true,59,59,0));
 check("campaign boundary survives seed removal",active_campaign_start({1,5,-5,1,-1},1)==0);
 check("campaign boundary uses latest flat transition",active_campaign_start({2,-2,1,5,-5,1,-1},1)==2);
 check("campaign boundary missing seed fails closed",active_campaign_start({5,-5,1,-1},1)==-1);
 check("campaign boundary inconsistent units fails closed",active_campaign_start({5},1)==-1);
 check("TP loss shift",std::fabs(shift(-50,.10,1,.01)-5)<1e-12); check("BUY TP away",std::fabs(adjtp(0,4002,-50,.10,1,.01)-4007)<1e-12); check("positive realized no pull",std::fabs(adjtp(0,4002,25,.10,1,.01)-4002)<1e-12);
 check("coverage hard cap",cov(100,115,80)==80);
 auto unordered=normalize_cov({75,35,100,55},100,100);
 check("unordered coverage keeps all unique targets",unordered.size()==4);
 check("unordered coverage sorts ascending",unordered==std::vector<double>({35,55,75,100}));
 auto capped=normalize_cov({120,55,100,80},115,80);
 check("capped duplicates collapse",capped.size()==2);
 check("capped targets sorted",capped==std::vector<double>({55,80}));
 auto partial=normalize_cov({55,35},100,100);
 check("final target appended",partial.size()==3);
 check("final target follows sorted explicit targets",partial==std::vector<double>({35,55,100}));
 check("ARCS staged raw",rawgen(1,100,0,35)==35); check("balanced subtract",rawgen(0,100,35,55)==20); check("broker min",clampmin(1,2)==2);
 check("raw floating MoneyTP ignores historical loss",money_tp(350,300));
 check("raw floating MoneyTP below target",!money_tp(299.99,300));
 check("PctDiff legacy shape hits tiny surplus",pctdiff(-2.21,2.47,10));
 check("PctDiff safety buffer blocks tiny surplus",!pctdiff_buffered(-2.21,2.47,10,1.0));
 check("PctDiff safety buffer allows realizable surplus",pctdiff_buffered(-10,15,10,3.0));
 check("PctDiff campaign debt blocks floating-only false profit",!pctdiff_economic_buffered(26.71,-9.42,10,-73.23,true,2.64));
 check("PctDiff debt survives Overlap seed removal",!pctdiff_economic_buffered(3.26,-.08,10,-5.385,true,2.40));
 check("PctDiff recovered campaign permits buffered flatten",pctdiff_economic_buffered(80,-20,10,-50,true,5));
 check("PctDiff history unavailable fails closed",!pctdiff_economic_buffered(80,-20,10,0,false,5));
 check("ticket-aware reserve reproduces XAU audit",std::fabs(execution_reserve(.24,.03,.11,9,.001,.10)-8.25)<1e-9);
 check("ticket-aware reserve keeps two-spread floor",std::fabs(execution_reserve(.24,0,.11,9,.001,.10)-5.28)<1e-9);
 check("ticket-aware reserve invalid metadata fails closed",execution_reserve(.24,.03,.11,9,0,.10)>1e200);
 check("ticket-aware reserve zero lots is zero",execution_reserve(.24,.03,0,9,.001,.10)==0);
 double overlap_reserve=execution_reserve(.24,.03,.08,2,.001,.10);
 check("Overlap two-ticket reserve",std::fabs(overlap_reserve-4.32)<1e-9);
 check("Overlap thin positive pair blocked",!overlap_safe(-8,9,overlap_reserve));
 check("Overlap robust pair allowed",overlap_safe(-8,15,overlap_reserve));
 check("Overlap invalid economics fail closed",!overlap_safe(-8,15,execution_reserve(.24,.03,.08,2,0,.10)));
 check("guard latch starts",latch_next(NONE,ACCOUNT,false)==ACCOUNT);
 check("guard latch survives threshold retreat",latch_next(ACCOUNT,NONE,false)==ACCOUNT);
 check("guard latch clears only flat",latch_next(ACCOUNT,NONE,true)==NONE);
 int serial=3; int open=3; open--; serial=next_serial(serial); double a=rearm_anchor(4020,3990,90,100,120,4030);
 check("post-peel capacity restored",concurrent_allowed(open,3)); check("post-peel serial P4",serial==4); check("P4 fresh gap from Peel exit",favorable(0,a,4049.9,4050,20)); check("P4 old 4035 region rejected",!favorable(0,a,4034.9,4035,20));
 serial=next_serial(serial); a=rearm_anchor(0,3990,140,100,120,4030);
 check("DCA epoch serial continues",serial==5); check("DCA epoch recovery from BE",favorable(0,a,4009.9,4010,20));
 std::cout<<"Pyramid T17.5 model: "<<pass_count<<" passed, "<<fail_count<<" failed\n";
 if(!fail_count) std::cout<<"ALL GREEN — T17.5 durable campaign + Overlap reserve + unordered Hedge coverage passed.\n";
 return fail_count?1:0;
}
