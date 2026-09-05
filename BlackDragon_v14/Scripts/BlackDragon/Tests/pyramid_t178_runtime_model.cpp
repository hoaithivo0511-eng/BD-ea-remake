#include <cmath>
#include <iostream>

enum Disposition { EXT=0, BYPASS=1, COORD=2 };

bool tp_wait_no_mutation(bool active, bool layerValid, long liveUnits,
                         long persistedOpened, long persistedRemaining,
                         bool tpHit)
{
    return active && layerValid && liveUnits > 0 &&
           liveUnits == persistedOpened && liveUnits == persistedRemaining &&
           !tpHit;
}

bool persistence_only_yields(bool consumed, bool semanticChangedNoPersist,
                             bool pending, bool reconcile)
{
    if(!consumed) return false;
    if(reconcile || pending || semanticChangedNoPersist) return false;
    return true;
}

bool expected_real_tp(bool realMode, bool configuredTp, bool ownerCore,
                      bool reasonTp, double programmedTp, double dealPrice,
                      double fillTolerance, bool liveCohortMatches)
{
    if(!realMode || !configuredTp || !ownerCore || !reasonTp) return false;
    if(programmedTp <= 0.0 || dealPrice <= 0.0 || fillTolerance < 0.0) return false;
    if(std::fabs(dealPrice - programmedTp) > fillTolerance + 1e-12) return false;
    return liveCohortMatches;
}

Disposition real_tp_disposition(bool expected, bool needsCoordination)
{
    if(!expected) return EXT;
    return needsCoordination ? COORD : BYPASS;
}

int main()
{
    int pass=0, fail=0;
    auto ck=[&](const char* n,bool ok){ if(ok) ++pass; else { ++fail; std::cerr<<"FAIL "<<n<<"\n"; } };

    ck("active stable no hit yields", tp_wait_no_mutation(true,true,70,70,70,false));
    ck("tp hit not yield", !tp_wait_no_mutation(true,true,70,70,70,true));
    ck("inactive not yield", !tp_wait_no_mutation(false,true,70,70,70,false));
    ck("invalid layer not yield", !tp_wait_no_mutation(true,false,70,70,70,false));
    ck("zero live not yield", !tp_wait_no_mutation(true,true,0,0,0,false));
    ck("opened mismatch delegates", !tp_wait_no_mutation(true,true,70,69,70,false));
    ck("remaining mismatch delegates", !tp_wait_no_mutation(true,true,70,70,69,false));

    ck("persist only consumed yields", persistence_only_yields(true,false,false,false));
    ck("semantic mutation consumes", !persistence_only_yields(true,true,false,false));
    ck("pending consumes", !persistence_only_yields(true,false,true,false));
    ck("reconcile consumes", !persistence_only_yields(true,false,false,true));
    ck("nonconsumed not override", !persistence_only_yields(false,false,false,false));

    ck("real tp expected", expected_real_tp(true,true,true,true,4081.376,4081.370,0.02,true));
    ck("virtual mode rejected", !expected_real_tp(false,true,true,true,4081.376,4081.376,0.02,true));
    ck("cfg tp off rejected", !expected_real_tp(true,false,true,true,4081.376,4081.376,0.02,true));
    ck("wrong owner rejected", !expected_real_tp(true,true,false,true,4081.376,4081.376,0.02,true));
    ck("wrong reason rejected", !expected_real_tp(true,true,true,false,4081.376,4081.376,0.02,true));
    ck("missing programmed tp rejected", !expected_real_tp(true,true,true,true,0,4081.376,0.02,true));
    ck("fill too far rejected", !expected_real_tp(true,true,true,true,4081.376,4081.50,0.02,true));
    ck("cohort mismatch rejected", !expected_real_tp(true,true,true,true,4081.376,4081.376,0.02,false));

    ck("expected preownership bypass", real_tp_disposition(true,false)==BYPASS);
    ck("expected owned coordinate", real_tp_disposition(true,true)==COORD);
    ck("unproven external", real_tp_disposition(false,true)==EXT);

    std::cout<<"T17.8 runtime fix model: "<<pass<<" passed, "<<fail<<" failed\n";
    if(fail==0) std::cout<<"ALL GREEN\n";
    return fail==0?0:1;
}
