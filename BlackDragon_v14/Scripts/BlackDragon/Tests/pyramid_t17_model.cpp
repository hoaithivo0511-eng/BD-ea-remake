#include <cmath>
#include <iostream>
#include <string>
#include <algorithm>

static int pass_count=0, fail_count=0;
static void check(const std::string& n,bool ok){if(ok)++pass_count;else{++fail_count;std::cout<<"FAIL: "<<n<<"\n";}}
static bool favorable(int d,double a,double b,double k,double g){return a>0&&b>0&&k>0&&g>=0&&(d==0?k>=a+g:b<=a-g);} 
static bool peel(int d,double o,double b,double a,double g){return o>0&&b>0&&a>0&&g>=0&&(d==0?b<=o-g:a>=o+g);} 
static double favp(int d,double be,double b,double a,double p){if(be<=0||p<=0)return 0;double x=d==0?b:a;return(d==0?x-be:be-x)/p;}
static double room(int d,double tp,double b,double a,double p){if(tp<=0||p<=0)return 1e300;return(d==0?tp-a:b-tp)/p;}
static double avail(double f,double r,double open,double pct){if(pct<=0)return 0;pct=std::min(pct,100.0);double e=f+r;if(e<=0)return 0;return std::max(e*pct/100.0-std::max(open,0.0),0.0);} 
static int next_serial(int highest){return highest<1?1:highest+1;}
static bool concurrent_allowed(int open,int cap){return cap>0&&open>=0&&open<cap;}
static double anchor(double newest,double be){return newest>0?newest:be;}
static bool timing(long last,long lastbar,long now,long bar,int mins){if(lastbar==bar&&bar>0)return false;if(mins>0&&last>0&&now<=last+(long)mins*60)return false;return true;}
static bool risk_applies(int mode,double pct){return mode!=0&&pct>0;}
static bool risk_mode_ready(int mode,double pct){return mode!=2||pct>0;}
static double econ(double f,double r){return f+r;}
static double shift(double r,double lots,double tv,double ts){if(r>=0||lots<=0||tv<=0||ts<=0)return 0;return(-r)/(tv*lots)*ts;}
static double adjtp(int d,double base,double r,double lots,double tv,double ts){double s=shift(r,lots,tv,ts);return d==0?base+s:base-s;}
static double cov(double s,double master,double hard){double v=s;if(master>0&&v>master)v=master;if(hard>0&&v>hard)v=hard;return v>0?v:0;}
static long pct_units(long core,double p){return core>0&&p>0?(long)std::floor(core*p/100.0+1e-9):0;}
static long rawgen(int policy,long core,long existing,double p){long d=pct_units(core,p);if(d<=0)return 0;if(policy==1)return d;existing=std::max(existing,0L);return d>existing?d-existing:0;}
static long clampmin(long x,long m){if(x<=0)return 0;if(m<=0)return x;return x<m?m:x;}

int main(){
 check("BUY favorable",favorable(0,4000,4000.9,4001,1)); check("SELL favorable",favorable(1,4000,3999,3999.1,1));
 check("BUY peel",peel(0,4001,4000.3,4000.4,0.7)); check("SELL peel",peel(1,3999,3999.6,3999.7,0.7));
 check("BUY favorable pips",std::fabs(favp(0,4000,4001,4001.1,0.1)-10)<1e-9); check("room TP",std::fabs(room(0,4002,4001.4,4001.5,0.1)-5)<1e-9);
 check("serial first",next_serial(0)==1); check("serial exceeds old 32",next_serial(32)==33); check("serial 100",next_serial(100)==101);
 check("concurrent 2/3 allowed",concurrent_allowed(2,3)); check("concurrent 3/3 blocked",!concurrent_allowed(3,3)); check("30 historical irrelevant",concurrent_allowed(0,3));
 check("anchor live wins",std::fabs(anchor(4020,3990)-4020)<1e-9); check("anchor falls back BE",std::fabs(anchor(0,3990)-3990)<1e-9);
 check("same bar blocked",!timing(100,100,110,100,0)); check("new bar delay off",timing(100,100,160,120,0)); check("minute delay blocks",!timing(100,100,200,120,5)); check("minute delay passes",timing(100,100,401,120,5));
 check("fixed ignores risk",!risk_applies(0,30)); check("multiplier risk optional on",risk_applies(1,30)); check("multiplier risk disabled zero",!risk_applies(1,0)); check("risk mode zero fail closed",!risk_mode_ready(2,0)); check("risk mode positive ready",risk_mode_ready(2,30));
 check("economic realized loss",std::fabs(econ(100,-40)-60)<1e-12); check("available risk loss",std::fabs(avail(100,-50,0,100)-50)<1e-12); check("available risk open",std::fabs(avail(100,0,20,30)-10)<1e-12);
 check("TP loss shift",std::fabs(shift(-50,.10,1,.01)-5)<1e-12); check("BUY TP away",std::fabs(adjtp(0,4002,-50,.10,1,.01)-4007)<1e-12); check("positive realized no pull",std::fabs(adjtp(0,4002,25,.10,1,.01)-4002)<1e-12);
 check("coverage hard cap",cov(100,115,80)==80); check("ARCS staged raw",rawgen(1,100,0,35)==35); check("balanced subtract",rawgen(0,100,35,55)==20); check("broker min",clampmin(1,2)==2);
 int serial=3; int open=3; open--; serial=next_serial(serial); double a=anchor(4020,3990);
 check("post-peel capacity restored",concurrent_allowed(open,3)); check("post-peel serial P4",serial==4); check("post-peel anchor newest live not extreme",std::fabs(a-4020)<1e-9); check("P4 gap from live anchor",favorable(0,a,4039.9,4040,20));
 open=0; serial=next_serial(serial); a=anchor(0,3990);
 check("all peeled anchor BE",std::fabs(a-3990)<1e-9); check("serial continues P5",serial==5); check("BE recovery trigger",favorable(0,a,4009.9,4010,20));
 std::cout<<"Pyramid T17.2 model: "<<pass_count<<" passed, "<<fail_count<<" failed\n";
 if(!fail_count) std::cout<<"ALL GREEN — T17.2 serial/no-extreme + timing + sizing policy passed.\n";
 return fail_count?1:0;
}
