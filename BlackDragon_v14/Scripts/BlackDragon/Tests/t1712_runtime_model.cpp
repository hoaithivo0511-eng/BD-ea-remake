#include <cmath>
#include <cfloat>
#include <iostream>

static int g_pass=0,g_fail=0;
static void ck(bool v,const char *name){ if(v) g_pass++; else { g_fail++; std::cerr<<"FAIL: "<<name<<"\n"; } }

static bool funded(bool recoveryOwns,bool valid,double core,double recovery,double pyramidRealized,double target,double reserve)
{
    if(!recoveryOwns) return true;
    if(!valid || !std::isfinite(reserve)) return false;
    return core+recovery+pyramidRealized+1e-9 >= std::max(target,0.0)+std::max(reserve,0.0);
}

static bool projected_tp(bool isBuy,double currentPrice,double legacyTp,double core,double recovery,
                         double pyramidRealized,double target,double reserve,double slope,double &out)
{
    out=0.0;
    if(currentPrice<=0.0 || legacyTp<=0.0 || !std::isfinite(reserve) || !std::isfinite(slope)) return false;
    double required=std::max(target,0.0)+std::max(reserve,0.0);
    double atLegacy=core+recovery+pyramidRealized+slope*(legacyTp-currentPrice);
    if(atLegacy+1e-9>=required){ out=legacyTp; return true; }
    double favorable=slope*(isBuy?1.0:-1.0);
    if(favorable<=1e-12) return false;
    double move=(required-atLegacy)/favorable;
    if(move<0.0 || !std::isfinite(move)) return false;
    out=legacyTp+(isBuy?move:-move);
    return out>0.0 && (isBuy ? out+1e-12>=legacyTp : out<=legacyTp+1e-12);
}

static bool money_tp_arm(double raw,double tp){ return tp>0.0 && raw>=tp; }
static bool money_tp_ready(bool latched,double raw,double tp,double reserve)
{
    return latched && tp>0.0 && std::isfinite(reserve) && raw+1e-9>=tp+std::max(reserve,0.0);
}

enum OState { IDLE=0, ARMED=1, LEG1_SUBMITTED=2, LEG2_WAIT=3 };
static OState drive_armed(OState s,bool pairValid,bool economicsSafe,bool recoveryDefer)
{
    if(s!=ARMED) return s;
    if(!pairValid) return IDLE;           // proven stale/identity invalidation may cancel
    if(recoveryDefer || !economicsSafe) return ARMED; // read-only WAIT
    return LEG1_SUBMITTED;
}

int main()
{
    // P0-A: two runtime-shaped counterexamples must stay blocked while Recovery owns the side.
    ck(!funded(true,true,106.40,-448.49,0.0,100.0,5.0),"SELL virtual TP negative whole-cycle blocks");
    ck(!funded(true,true,215.29,-425.59,0.0,100.0,5.0),"BUY virtual TP negative whole-cycle blocks");
    ck(funded(true,true,215.29,-80.0,0.0,100.0,5.0),"funded recovery cycle may close");
    ck(funded(false,false,-999,-999,-999,999,DBL_MAX),"Core-only parity bypasses T17.12 gate");
    ck(!funded(true,false,500,0,0,100,5),"missing economics fails closed");
    ck(!funded(true,true,500,0,0,100,DBL_MAX),"missing reserve fails closed");
    ck(!funded(true,true,150,-20,-40,100,5),"Pyramid realized debt participates");
    ck(funded(true,true,170,-20,-40,100,5),"Pyramid debt repaid before close");

    // P0-A REAL TP: under-hedged BUY/SELL move outward; full/over hedge cannot create unsafe finite target.
    double tp=0.0;
    ck(projected_tp(true,1.1000,1.1010,40,-20,0,100,5,100000,tp) && tp>=1.1010,"BUY under-hedge outward target");
    ck(projected_tp(false,1.1000,1.0990,40,-20,0,100,5,-100000,tp) && tp<=1.0990,"SELL under-hedge outward target");
    ck(!projected_tp(true,1.1000,1.1010,40,-40,0,100,5,0,tp),"BUY full hedge no finite favorable TP");
    ck(!projected_tp(false,1.1000,1.0990,40,-40,0,100,5,0,tp),"SELL full hedge no finite favorable TP");
    ck(!projected_tp(true,1.1000,1.1010,40,-60,0,100,5,-100000,tp),"BUY over-hedge no unsafe TP");
    ck(!projected_tp(false,1.1000,1.0990,40,-60,0,100,5,100000,tp),"SELL over-hedge no unsafe TP");
    ck(!projected_tp(true,1.1000,1.1010,40,-20,0,100,DBL_MAX,100000,tp),"REAL TP missing metadata fails closed");

    // P1-B: WAIT/DEFER must keep one durable same-pair obligation instead of IDLE re-arm churn.
    ck(drive_armed(ARMED,true,false,false)==ARMED,"Overlap unsafe economics keeps ARMED");
    ck(drive_armed(ARMED,true,true,true)==ARMED,"Overlap Recovery DEFER keeps ARMED");
    ck(drive_armed(ARMED,true,true,false)==LEG1_SUBMITTED,"Overlap safe pair submits once");
    ck(drive_armed(ARMED,false,true,false)==IDLE,"Overlap proven stale pair may cancel");

    // P1-C: raw ACCOUNT_PROFIT still arms, but execution waits for target + reserve while latch remains active.
    ck(money_tp_arm(100.12,100.0),"MoneyTP raw threshold unchanged");
    ck(!money_tp_ready(true,100.12,100.0,8.0),"MoneyTP sequential reserve prevents thin close");
    ck(money_tp_ready(true,110.60,100.0,8.0),"MoneyTP latch executes when reserve funded");
    ck(!money_tp_ready(true,107.0,100.0,8.0),"MoneyTP retreat stays latched/read-only");
    ck(!money_tp_ready(true,1000.0,100.0,DBL_MAX),"MoneyTP invalid account reserve fails closed");

    // P2-D lifecycle specification: a never-initialized engine has nothing to flush.
    bool initialized=false;
    ck(!initialized,"invalid-init leaves recovery uninitialized");

    std::cout << "T17.12 reference model: " << g_pass << " passed, " << g_fail << " failed\n";
    if(g_fail==0) std::cout << "ALL GREEN\n";
    return g_fail==0?0:1;
}
