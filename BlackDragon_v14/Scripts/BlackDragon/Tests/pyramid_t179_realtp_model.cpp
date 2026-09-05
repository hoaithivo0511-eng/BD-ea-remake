#include <algorithm>
#include <array>
#include <cmath>
#include <iostream>

enum Proof { EXTERNAL=0, PREOWNERSHIP=1, EPOCH=2 };

bool strict_tp(bool realMode,bool configured,bool owner,bool reasonTp,
               double programmed,double fill,double tolerance)
{
    return realMode && configured && owner && reasonTp && programmed>0 && fill>0 &&
           tolerance>=0 && std::fabs(programmed-fill)<=tolerance+1e-12;
}

Proof classify(bool strict,bool recoveryOwns,bool epochActive,
               bool targetMatches,bool idMatches)
{
    if(!strict) return EXTERNAL;
    if(!recoveryOwns) return PREOWNERSHIP;
    return epochActive && targetMatches && idMatches ? EPOCH : EXTERNAL;
}

bool starts(bool active,bool settling,bool hit,bool callback)
{ return active && !settling && (hit || callback); }
bool blocks(bool fault,bool settling) { return fault || settling; }
bool complete(bool active,bool settling,long core,long hedge,bool reconcile)
{ return active && settling && core<=0 && hedge<=0 && !reconcile; }
bool mod_ok(unsigned long long requested,bool selected,unsigned long long selectedTicket,
            bool symbol,bool owner,bool type,double volume)
{ return requested && selected && selectedTicket==requested && symbol && owner && type && volume>0; }

int main()
{
    int pass=0,fail=0;
    auto ck=[&](const char*n,bool ok){if(ok)++pass;else{++fail;std::cerr<<"FAIL "<<n<<"\n";}};
    ck("strict expected",strict_tp(true,true,true,true,4079.896,4079.891,0.02));
    ck("strict rejects virtual",!strict_tp(false,true,true,true,4079.896,4079.896,0.02));
    ck("strict rejects cfg off",!strict_tp(true,false,true,true,4079.896,4079.896,0.02));
    ck("strict rejects owner",!strict_tp(true,true,false,true,4079.896,4079.896,0.02));
    ck("strict rejects reason",!strict_tp(true,true,true,false,4079.896,4079.896,0.02));
    ck("strict rejects fill",!strict_tp(true,true,true,true,4079.896,4080.5,0.02));
    ck("preownership ignores mutable cohort",classify(true,false,false,false,false)==PREOWNERSHIP);
    ck("owned exact epoch",classify(true,true,true,true,true)==EPOCH);
    ck("owned missing epoch external",classify(true,true,false,true,true)==EXTERNAL);
    ck("owned wrong target external",classify(true,true,true,false,true)==EXTERNAL);
    ck("owned new id external",classify(true,true,true,true,false)==EXTERNAL);
    ck("unproven external",classify(false,false,true,true,true)==EXTERNAL);
    ck("price starts settlement",starts(true,false,true,false));
    ck("callback starts settlement",starts(true,false,false,true));
    ck("inactive cannot settle",!starts(false,false,true,true));
    ck("already settling not restarted",!starts(true,true,true,true));
    ck("settling blocks",blocks(false,true));
    ck("fault blocks",blocks(true,false));
    ck("idle allows",!blocks(false,false));
    ck("complete flat",complete(true,true,0,0,false));
    ck("core delays complete",!complete(true,true,1,0,false));
    ck("hedge delays complete",!complete(true,true,0,1,false));
    ck("reconcile delays complete",!complete(true,true,0,0,true));
    ck("unsettled not complete",!complete(true,false,0,0,false));
    ck("modify exact live",mod_ok(10,true,10,true,true,true,0.1));
    ck("modify rejects zero",!mod_ok(0,true,0,true,true,true,0.1));
    ck("modify rejects vanished",!mod_ok(10,false,0,true,true,true,0.1));
    ck("modify rejects reselection drift",!mod_ok(10,true,14,true,true,true,0.1));
    ck("modify rejects symbol",!mod_ok(10,true,10,false,true,true,0.1));
    ck("modify rejects owner",!mod_ok(10,true,10,true,false,true,0.1));
    ck("modify rejects type",!mod_ok(10,true,10,true,true,false,0.1));
    ck("modify rejects flat",!mod_ok(10,true,10,true,true,true,0.0));

    // Integrated fixture: four old Core identifiers are frozen before price hit.
    const std::array<unsigned long long,4> epoch{{10,11,12,13}};
    const unsigned long long newCore=14;
    bool settling=starts(true,false,true,false);
    int submittedAdds=0, expectedCallbacks=0, externalLatch=0;
    bool pyramidEligible=true;
    if(pyramidEligible && !blocks(false,settling)) ++submittedAdds;
    for(auto id:epoch) {
        bool member=std::find(epoch.begin(),epoch.end(),id)!=epoch.end();
        Proof p=classify(strict_tp(true,true,true,true,4079.896,4079.891,0.02),
                         true,true,true,member);
        if(p==EPOCH) ++expectedCallbacks; else ++externalLatch;
        if(!blocks(false,settling)) ++submittedAdds; // interleaved OnTick
    }
    bool newMember=std::find(epoch.begin(),epoch.end(),newCore)!=epoch.end();
    ck("fixture freezes before add",settling);
    ck("fixture no Core/Pyramid interleave",submittedAdds==0);
    ck("fixture four old TP expected",expectedCallbacks==4);
    ck("fixture no external/manual latch",externalLatch==0);
    ck("fixture new Core excluded",!newMember && classify(true,true,true,true,newMember)==EXTERNAL);
    ck("fixture no stale modify",!mod_ok(10,false,0,true,true,true,0.1));
    ck("fixture no reconcile",complete(true,true,0,0,false));
    settling=false;
    ck("fixture later campaign allowed",!blocks(false,settling));

    std::cout<<"T17.9 REAL-TP interleave model: "<<pass<<" passed, "<<fail<<" failed\n";
    if(!fail) std::cout<<"ALL GREEN\n";
    return fail?1:0;
}

