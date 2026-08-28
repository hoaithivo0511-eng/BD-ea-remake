#include <cmath>
#include <iostream>
#include <string>

enum State { CORE_ONLY=0, ARMED=1, HEDGE_BUILDING=2, HEDGE_ACTIVE=3,
             HEDGE_LOCKED=4, TP_PENDING=5, RECONCILE=6 };
enum Policy { BYPASS=0, COORDINATE=1, DEFER=2 };

static Policy capability_policy(State state, bool activeReady,
                                bool recoveryMutationPending,
                                bool journalMutationPending,
                                bool coordinatorPending)
{
    if(!activeReady || recoveryMutationPending || journalMutationPending ||
       coordinatorPending)
        return DEFER;
    if(state==CORE_ONLY) return BYPASS;
    if(state==ARMED || state==HEDGE_BUILDING || state==HEDGE_ACTIVE ||
       state==HEDGE_LOCKED)
        return COORDINATE;
    return DEFER;
}

static long percent_units(long core, double percent)
{
    if(core<=0 || percent<=0.0) return 0;
    return static_cast<long>(std::floor(static_cast<double>(core)*percent/100.0+1e-9));
}

static bool retained_within_cap(long projectedCore, long retainedHedge,
                                double hardCapPercent)
{
    if(projectedCore<0 || retainedHedge<0) return false;
    if(hardCapPercent<=0.0) return true;
    return retainedHedge<=percent_units(projectedCore,hardCapPercent);
}

static long refreshed_generation_target(long refreshedCore,
                                        long retainedBeforeGeneration,
                                        long liveGeneration,
                                        double finalCoverage)
{
    long desiredTotal=percent_units(refreshedCore,finalCoverage);
    long computed=desiredTotal>retainedBeforeGeneration ?
                  desiredTotal-retainedBeforeGeneration : 0;
    return liveGeneration>computed ? liveGeneration : computed;
}

int main()
{
    int pass=0,fail=0;
    auto ck=[&](bool ok,const std::string &name){
        if(ok) ++pass; else { ++fail; std::cerr<<"FAIL: "<<name<<"\n"; }
    };

    ck(capability_policy(HEDGE_BUILDING,true,false,false,false)==COORDINATE,
       "quiet HEDGE_BUILDING coordinates Overlap");
    ck(capability_policy(HEDGE_BUILDING,true,true,false,false)==DEFER,
       "durable Recovery mutation blocks Overlap");
    ck(capability_policy(HEDGE_BUILDING,true,false,true,false)==DEFER,
       "execution journal mutation blocks Overlap");
    ck(capability_policy(HEDGE_BUILDING,true,false,false,true)==DEFER,
       "existing coordinator obligation blocks Overlap");
    ck(capability_policy(HEDGE_BUILDING,false,false,false,false)==DEFER,
       "unready Recovery blocks Overlap");
    ck(capability_policy(TP_PENDING,true,false,false,false)==DEFER,
       "semantic mutation state remains blocked even when journal is quiet");

    // Owner-approved stateful regression:
    // economics-safe -> quiet BUILDING -> coordinated trim -> target refresh -> ladder continues.
    const bool economicsSafe=true;
    const long coreBefore=100, trimUnits=20, coreAfter=coreBefore-trimUnits;
    const long retainedPrior=50, liveGeneration=18;
    const long retainedHedge=retainedPrior+liveGeneration;
    const double hardCap=90.0;
    ck(economicsSafe &&
       capability_policy(HEDGE_BUILDING,true,false,false,false)==COORDINATE,
       "economics-safe BUILDING candidate reaches coordinated route");
    ck(retained_within_cap(coreAfter,retainedHedge,hardCap),
       "projected Core trim keeps retained Hedge within 90 percent hard cap");
    long refreshedTarget=refreshed_generation_target(coreAfter,retainedPrior,
                                                     liveGeneration,hardCap);
    ck(refreshedTarget==22,
       "post-trim denominator refresh rebases current generation target to 22 units");
    ck(refreshedTarget-liveGeneration==4,
       "refreshed BUILDING generation continues ladder for four units");
    ck(!retained_within_cap(70,retainedHedge,hardCap),
       "trim projecting 68 Hedge over 63-unit hard cap is blocked before mutation");
    ck(retained_within_cap(0,0,hardCap) && !retained_within_cap(0,1,hardCap),
       "flat Core permits no retained Hedge under an enabled hard cap");

    std::cout<<"T17.15 Overlap capability model: "<<pass
             <<" passed, "<<fail<<" failed\n";
    if(fail==0) std::cout<<"ALL GREEN\n";
    return fail==0?0:1;
}
