#include <cmath>
#include <iostream>
#include <string>

static bool broker_partial(long live,long previousTarget,int stageNo,
                           long stageTarget,int admittedStage,
                           long admittedTarget)
{
    if(live<=previousTarget || live>=stageTarget) return false;
    return admittedStage==stageNo && admittedTarget==stageTarget;
}

static double recovery_threshold(double required)
{
    return required>0.0 ? required*1.10 : 0.0;
}

static bool embargo_blocks(bool active,double freeMargin,double threshold)
{
    if(!active) return false;
    if(threshold<=0.0) return true;
    return freeMargin+1e-8<threshold;
}

struct Ladder {
    long live=80;
    long previous=80;
    long target=100;
    int stage=5;
    int admittedStage=0;
    long admittedTarget=0;
    int opens=0;

    void rebase(long nextTarget) {
        target=nextTarget;
        admittedStage=0;
        admittedTarget=0;
    }
    bool try_open(bool newBar,bool gapHit,bool hedgeProfitable,long maxChild) {
        bool partial=broker_partial(live,previous,stage,target,
                                    admittedStage,admittedTarget);
        if(!partial && live>0 && (!newBar || !gapHit || !hedgeProfitable))
            return false;
        admittedStage=stage;
        admittedTarget=target;
        long remaining=target-live;
        if(remaining<=0) return false;
        live+=remaining<maxChild?remaining:maxChild;
        ++opens;
        return true;
    }
};

int main()
{
    int pass=0,fail=0;
    auto ck=[&](bool ok,const std::string &name){
        if(ok) ++pass; else { ++fail; std::cerr<<"FAIL: "<<name<<"\n"; }
    };

    ck(broker_partial(90,80,5,100,5,100),
       "exact admitted broker child continues one logical stage");
    ck(!broker_partial(90,80,5,110,5,100),
       "denominator rebase cannot impersonate partial child");
    ck(!broker_partial(80,80,5,100,5,100),
       "stage boundary is not partial");
    ck(!broker_partial(100,80,5,100,5,100),
       "completed stage is not partial");
    ck(!broker_partial(90,80,6,100,5,100),
       "different logical stage is not partial");

    Ladder l;
    ck(!l.try_open(false,true,true,10),"new stage waits for new bar");
    ck(!l.try_open(true,false,true,10),"new stage waits for favorable gap");
    ck(!l.try_open(true,true,false,10),"losing Hedge blocks new stage");
    ck(l.try_open(true,true,true,10) && l.live==90 && l.opens==1,
       "gated stage admits first broker child");
    ck(l.try_open(false,false,false,10) && l.live==100 && l.opens==2,
       "genuine broker split finishes without second stage gap");

    // economics-safe -> HEDGE_BUILDING -> coordinated Overlap -> refresh ->
    // continue ladder. The trim/rebase clears prior admission authority.
    l.live=68; l.previous=60; l.stage=4; l.admittedStage=4;l.admittedTarget=72;
    l.rebase(72); // post-Overlap Core80, retained/live68, hard-cap target72
    ck(!l.try_open(true,true,false,4) && l.live==68,
       "post-Overlap refresh re-runs profit lock before refill");
    ck(l.try_open(true,true,true,2) && l.live==70,
       "post-Overlap refreshed target resumes after all gates");
    ck(l.try_open(false,false,false,2) && l.live==72,
       "post-Overlap true partial child completes admitted target");

    // Core grows again while HEDGE_BUILDING. Even if stage number is unchanged,
    // the new target invalidates the old admission and cannot open continuously.
    l.previous=60; l.stage=4; l.rebase(90);
    int before=l.opens;
    ck(!l.try_open(true,true,false,10) && l.opens==before,
       "Core denominator growth cannot bypass Hedge profit lock");
    ck(l.try_open(true,true,true,10) && l.opens==before+1,
       "rebased ladder may continue once safety gates recover");

    double threshold=recovery_threshold(100.0);
    ck(std::fabs(threshold-110.0)<1e-9,"NO_MONEY recovery threshold has 10 percent buffer");
    ck(embargo_blocks(true,-10.0,threshold),"negative free margin blocks every risk add");
    ck(embargo_blocks(true,100.0,threshold),"new bar with original margin remains blocked");
    ck(embargo_blocks(true,109.99,threshold),"hysteresis prevents edge reopen churn");
    ck(!embargo_blocks(true,110.0,threshold),"recovered margin clears embargo deterministically");
    ck(!embargo_blocks(false,-1000.0,threshold),"inactive embargo never blocks");
    ck(embargo_blocks(true,1000.0,0.0),"unknown required margin fails closed");

    std::cout<<"T17.16 rebase/capacity model: "<<pass
             <<" passed, "<<fail<<" failed\n";
    if(fail==0) std::cout<<"ALL GREEN\n";
    return fail==0?0:1;
}
