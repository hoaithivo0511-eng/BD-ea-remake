#include <cmath>
#include <iostream>

enum Direction { CORE_BUY = 0, CORE_SELL = 1 };
enum Phase { NONE=0, COLLECTING=1, WAIT_RESET=2, ARMED=3,
             TRIGGER_PENDING=4, IN_CYCLE=5, EXHAUSTED=6 };

bool positive_chain(double cash, double epsilon)
{
    return epsilon >= 0.0 && cash >= -epsilon;
}

bool eligible_terminal(bool exactOwned, int generation, int maxGeneration,
                       long coreUnits, long hedgeUnits, double cash,
                       double epsilon, int cycles, int maxCycles)
{
    return exactOwned && maxGeneration > 0 && generation >= maxGeneration &&
           coreUnits > 0 && hedgeUnits == 0 && positive_chain(cash, epsilon) &&
           maxCycles > 0 && cycles < maxCycles;
}

bool reset_hit(Direction dir, long anchor, long bid, long ask, long buffer)
{
    if(anchor <= 0 || buffer <= 0) return false;
    return dir == CORE_BUY ? ask >= anchor + buffer
                           : bid <= anchor - buffer;
}

bool return_hit(Direction dir, long anchor, long bid, long ask)
{
    if(anchor <= 0) return false;
    return dir == CORE_BUY ? bid <= anchor : ask >= anchor;
}

bool blocks_dca(Phase phase)
{
    return phase == WAIT_RESET || phase == ARMED ||
           phase == TRIGGER_PENDING || phase == EXHAUSTED;
}

bool blocks_pyramid_add(Phase phase)
{
    return phase == TRIGGER_PENDING || phase == EXHAUSTED;
}

bool explicitly_allows_pyramid_add(Phase phase)
{
    return phase == WAIT_RESET || phase == ARMED;
}

Phase terminal_phase(int cycles, int maxCycles)
{
    return maxCycles > 0 && cycles < maxCycles ? WAIT_RESET : EXHAUSTED;
}

int main()
{
    int pass=0, fail=0;
    auto ck=[&](const char *name, bool ok) {
        if(ok) ++pass;
        else { ++fail; std::cerr << "FAIL " << name << "\n"; }
    };

    ck("positive cash", positive_chain(12.5, 1e-8));
    ck("zero cash accepted", positive_chain(0.0, 1e-8));
    ck("rounding epsilon accepted", positive_chain(-5e-9, 1e-8));
    ck("negative chain rejected", !positive_chain(-0.01, 1e-8));

    ck("eligible terminal", eligible_terminal(true,3,3,185,0,8.2,1e-8,0,2));
    ck("exact ownership required", !eligible_terminal(false,3,3,185,0,8.2,1e-8,0,2));
    ck("terminal generation required", !eligible_terminal(true,2,3,185,0,8.2,1e-8,0,2));
    ck("core required", !eligible_terminal(true,3,3,0,0,8.2,1e-8,0,2));
    ck("all hedge must close", !eligible_terminal(true,3,3,185,1,8.2,1e-8,0,2));
    ck("positive aggregate required", !eligible_terminal(true,3,3,185,0,-8.2,1e-8,0,2));
    ck("zero disables", !eligible_terminal(true,3,3,185,0,8.2,1e-8,0,0));
    ck("outer cap enforced", !eligible_terminal(true,3,3,185,0,8.2,1e-8,2,2));

    ck("buy reset below boundary waits", !reset_hit(CORE_BUY,1000,1008,1009,10));
    ck("buy reset exact Ask boundary", reset_hit(CORE_BUY,1000,1009,1010,10));
    ck("sell reset above boundary waits", !reset_hit(CORE_SELL,1000,991,992,10));
    ck("sell reset exact Bid boundary", reset_hit(CORE_SELL,1000,990,991,10));
    ck("zero reset buffer invalid", !reset_hit(CORE_BUY,1000,1000,1000,0));

    ck("buy return exact Bid anchor", return_hit(CORE_BUY,1000,1000,1001));
    ck("buy return above waits", !return_hit(CORE_BUY,1000,1001,1002));
    ck("sell return exact Ask anchor", return_hit(CORE_SELL,1000,999,1000));
    ck("sell return below waits", !return_hit(CORE_SELL,1000,998,999));

    ck("WAIT blocks DCA", blocks_dca(WAIT_RESET));
    ck("ARMED blocks DCA", blocks_dca(ARMED));
    ck("WAIT allows Pyramid ADD", !blocks_pyramid_add(WAIT_RESET));
    ck("ARMED allows Pyramid ADD", !blocks_pyramid_add(ARMED));
    ck("WAIT bypasses legacy pause-state gate", explicitly_allows_pyramid_add(WAIT_RESET));
    ck("ARMED bypasses legacy pause-state gate", explicitly_allows_pyramid_add(ARMED));
    ck("trigger-pending blocks both growth paths",
       blocks_dca(TRIGGER_PENDING) && blocks_pyramid_add(TRIGGER_PENDING));
    ck("in-cycle defers to existing policy",
       !blocks_dca(IN_CYCLE) && !blocks_pyramid_add(IN_CYCLE));
    ck("exhausted blocks both growth paths",
       blocks_dca(EXHAUSTED) && blocks_pyramid_add(EXHAUSTED));
    ck("first terminal close waits reset", terminal_phase(0,2)==WAIT_RESET);
    ck("last allowed close waits reset", terminal_phase(1,2)==WAIT_RESET);
    ck("cap terminal is exhausted", terminal_phase(2,2)==EXHAUSTED);

    std::cout << "T17.19 Recovery re-entry model: " << pass
              << " passed, " << fail << " failed\n";
    if(fail==0) std::cout << "ALL GREEN\n";
    return fail==0 ? 0 : 1;
}
