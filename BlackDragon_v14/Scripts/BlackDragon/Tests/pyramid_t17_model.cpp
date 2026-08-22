#include <cmath>
#include <iostream>
#include <string>
#include <vector>
#include <algorithm>

// T17.1 model oracle: stateful campaign economics + monotonic re-entry + Hedge hard-cap policy.
static int pass_count=0, fail_count=0;
static void check(const std::string& name, bool ok){ if(ok){++pass_count;} else {++fail_count; std::cout<<"FAIL: "<<name<<"\n";} }

static bool favorable(int dir,double anchor,double bid,double ask,double gap){
    if(anchor<=0||bid<=0||ask<=0||gap<0) return false;
    return dir==0 ? ask>=anchor+gap : bid<=anchor-gap;
}
static bool peel(int dir,double open,double bid,double ask,double gap){
    if(open<=0||bid<=0||ask<=0||gap<0) return false;
    return dir==0 ? bid<=open-gap : ask>=open+gap;
}
static double favorable_pips(int dir,double be,double bid,double ask,double pip){
    if(be<=0||pip<=0) return 0;
    const double px=dir==0?bid:ask;
    return (dir==0?px-be:be-px)/pip;
}
static double room_tp(int dir,double tp,double bid,double ask,double pip){
    if(tp<=0||pip<=0) return 1e300;
    return (dir==0?tp-ask:bid-tp)/pip;
}
static double risk_cap(double profit,double pct,double risk_per_lot){
    if(profit<=0||pct<=0||risk_per_lot<=0) return 0;
    pct=std::min(pct,100.0);
    return profit*pct/100.0/risk_per_lot;
}
static double available_risk(double floating,double realized,double open_risk,double pct){
    if(pct<=0) return 0;
    pct=std::min(pct,100.0);
    double economic=floating+realized;
    if(economic<=0) return 0;
    return std::max(economic*pct/100.0-std::max(open_risk,0.0),0.0);
}
static int next_level(int highest){ return highest<1?1:highest+1; }
static bool cumulative_allowed(int adds,int max_adds){ return max_adds>0 && adds>=0 && adds<max_adds; }
static double campaign_economic(double floating,double realized){ return floating+realized; }
static double tp_shift(double realized,double lots,double tick_value,double tick_size){
    if(realized>=0||lots<=0||tick_value<=0||tick_size<=0) return 0;
    return (-realized)/(tick_value*lots)*tick_size;
}
static double adjusted_tp(int dir,double base,double realized,double lots,double tick_value,double tick_size){
    if(base<=0) return base;
    double s=tp_shift(realized,lots,tick_value,tick_size);
    return dir==0?base+s:base-s;
}
static double effective_cov(double stage,double master,double hard){
    double v=stage;
    if(master>0 && v>master) v=master;
    if(hard>0 && v>hard) v=hard;
    return v>0?v:0;
}
static long pct_units(long core,double pct){
    if(core<=0||pct<=0) return 0;
    return (long)std::floor(core*pct/100.0+1e-9);
}
static long raw_generation(int policy,long core,long existing,double pct){
    long desired=pct_units(core,pct);
    if(desired<=0) return 0;
    if(policy==1) return desired;
    existing=std::max(existing,0L);
    return desired>existing?desired-existing:0;
}
static long clamp_min(long raw,long min_units){
    if(raw<=0) return 0;
    if(min_units<=0) return raw;
    return raw<min_units?min_units:raw;
}
static double runtime_hedge_pct(int mode,double requested,double configured,double hard){
    if(mode==0 || requested<=0) return requested;
    if(std::fabs(requested-configured)>1e-9) return requested;
    if(hard>0 && requested>hard) return hard;
    return requested;
}
static int parse_level(const std::string& c){
    if(c.rfind("BDP|",0)!=0) return -1;
    auto p=c.find("L="); if(p==std::string::npos) return -1; p+=2;
    auto e=c.find('|',p); return std::stoi(c.substr(p,e-p));
}

int main(){
    check("BUY favorable hit", favorable(0,4000.0,4000.9,4001.0,1.0));
    check("BUY favorable miss", !favorable(0,4000.0,4000.8,4000.9,1.0));
    check("SELL favorable hit", favorable(1,4000.0,3999.0,3999.1,1.0));
    check("SELL favorable miss", !favorable(1,4000.0,3999.1,3999.2,1.0));
    check("BUY LIFO peel hit", peel(0,4001.0,4000.3,4000.4,0.7));
    check("BUY LIFO peel miss", !peel(0,4001.0,4000.31,4000.41,0.7));
    check("SELL LIFO peel hit", peel(1,3999.0,3999.6,3999.7,0.7));
    check("SELL LIFO peel miss", !peel(1,3999.0,3999.59,3999.69,0.7));
    check("BUY favorable pips", std::fabs(favorable_pips(0,4000.0,4001.0,4001.1,0.1)-10.0)<1e-9);
    check("SELL favorable pips", std::fabs(favorable_pips(1,4000.0,3998.9,3999.0,0.1)-10.0)<1e-9);
    check("BUY room to TP", std::fabs(room_tp(0,4002.0,4001.4,4001.5,0.1)-5.0)<1e-9);
    check("SELL room to TP", std::fabs(room_tp(1,3998.0,3998.5,3998.6,0.1)-5.0)<1e-9);
    check("legacy profit-funded cap", std::fabs(risk_cap(20.0,30.0,100.0)-0.06)<1e-12);
    check("legacy risk cap pct clamps 100", std::fabs(risk_cap(20.0,150.0,100.0)-0.20)<1e-12);
    check("legacy risk cap no profit zero", risk_cap(0.0,30.0,100.0)==0.0);
    check("legacy risk cap no budget zero", risk_cap(20.0,0.0,100.0)==0.0);
    check("coverage master cap", effective_cov(115.0,100.0,115.0)==100.0);
    check("coverage hard cap", effective_cov(100.0,115.0,80.0)==80.0);
    check("coverage unchanged", effective_cov(55.0,100.0,100.0)==55.0);
    check("ARCS layered raw 35 pct", raw_generation(1,100,0,35.0)==35);
    check("balanced raw subtract existing", raw_generation(0,100,35,55.0)==20);
    check("balanced already covered zero", raw_generation(0,100,60,55.0)==0);
    check("broker minimum clamp", clamp_min(1,2)==2);
    check("zero never invents hedge", clamp_min(0,2)==0);
    check("runtime hard cap OFF preserves configured target", std::fabs(runtime_hedge_pct(0,115.0,115.0,75.0)-115.0)<1e-12);
    check("runtime hard cap ON caps configured target", std::fabs(runtime_hedge_pct(1,115.0,115.0,75.0)-75.0)<1e-12);
    check("runtime hard cap leaves explicit stage percent unchanged", std::fabs(runtime_hedge_pct(1,55.0,115.0,75.0)-55.0)<1e-12);
    check("role comment level", parse_level("BDP|D=0|L=4|R=2")==4);
    check("non pyramid comment rejected", parse_level("EA Black Dragon|4")==-1);
    check("campaign first level", next_level(0)==1);
    check("campaign level monotonic after peel", next_level(30)==31);
    check("cumulative add 29 of 30 allowed", cumulative_allowed(29,30));
    check("cumulative add 30 of 30 blocked", !cumulative_allowed(30,30));
    check("campaign economic includes realized loss", std::fabs(campaign_economic(100.0,-40.0)-60.0)<1e-12);
    check("campaign economic hidden loss", std::fabs(campaign_economic(300.0,-500.0)+200.0)<1e-12);
    check("available risk subtracts realized loss", std::fabs(available_risk(100.0,-50.0,0.0,100.0)-50.0)<1e-12);
    check("available risk subtracts open Pyramid risk", std::fabs(available_risk(100.0,0.0,20.0,30.0)-10.0)<1e-12);
    check("available risk exhausted by realized loss", available_risk(100.0,-100.0,0.0,100.0)==0.0);
    check("available risk cannot go negative", available_risk(100.0,0.0,40.0,30.0)==0.0);
    check("TP loss recovery shift", std::fabs(tp_shift(-50.0,0.10,1.0,0.01)-5.0)<1e-12);
    check("BUY economic TP shifted away", std::fabs(adjusted_tp(0,4002.0,-50.0,0.10,1.0,0.01)-4007.0)<1e-12);
    check("SELL economic TP shifted away", std::fabs(adjusted_tp(1,3998.0,-50.0,0.10,1.0,0.01)-3993.0)<1e-12);
    check("positive realized never pulls TP closer", std::fabs(adjusted_tp(0,4002.0,25.0,0.10,1.0,0.01)-4002.0)<1e-12);
    check("rearm below new historical extension blocked", !favorable(0,4002.0,4002.8,4002.9,1.0));
    check("rearm only after new historical extension", favorable(0,4002.0,4002.9,4003.0,1.0));
    check("hidden realized loss blocks 300 TP", !(campaign_economic(300.0,-500.0)>=300.0));
    std::cout << "Pyramid T17.1 model: " << pass_count << " passed, " << fail_count << " failed\n";
    if(fail_count==0) std::cout << "ALL GREEN — T17.1 campaign ledger/re-entry/TP economics + Hedge policy passed.\n";
    return fail_count==0?0:1;
}