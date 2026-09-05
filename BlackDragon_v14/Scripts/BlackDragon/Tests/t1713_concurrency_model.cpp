#include <cmath>
#include <iostream>
#include <string>

enum RMode { R_OFF=0, R_SHADOW=1, R_ACTIVE=2 };
enum RState {
    R_CORE_ONLY=0, R_ARMED, R_HEDGE_BUILDING, R_HEDGE_ACTIVE,
    R_HEDGE_TP_PENDING, R_CORE_CLOSE_PENDING, R_HEDGE_LOCK_PENDING,
    R_HEDGE_LOCKED, R_REHEDGE_PENDING, R_PAUSE_SOFT, R_PAUSE_HARD,
    R_RECONCILE_REQUIRED, R_GLOBAL_STOP, R_COMPLETED
};
enum OState {
    O_IDLE=0, O_PAIR_ARMED, O_LEG1_SUBMITTED, O_LEG1_CONFIRMED,
    O_LEG2_RECHECK, O_LEG2_WAIT_SAFE, O_LEG2_SUBMITTED, O_COMPLETE,
    O_RECONCILE
};

static bool recovery_core_growth_allows(int mode, bool cont, int state)
{
    if(mode != R_ACTIVE) return true;
    if(state == R_CORE_ONLY || state == R_ARMED) return true;
    if(!cont) return false;
    return state == R_HEDGE_BUILDING || state == R_HEDGE_ACTIVE ||
           state == R_HEDGE_LOCKED || state == R_REHEDGE_PENDING;
}

static bool overlap_blocks_core_growth(int state)
{
    return state == O_LEG1_SUBMITTED || state == O_LEG2_SUBMITTED ||
           state == O_RECONCILE;
}

static bool overlap_may_commit_pair(bool economicsSafe, bool recoveryDefer)
{
    return economicsSafe && !recoveryDefer;
}

static bool buy_dca_due(double lastOpen, double ask, double gapPips, double pipPrice)
{
    return ask <= lastOpen - gapPips * pipPrice + 1e-12;
}

static long percent_units(long coreUnits, double pct)
{
    return (long)std::floor(coreUnits * pct / 100.0 + 1e-9);
}

struct ExecutionSpy {
    int openCalls = 0;
    bool openMarket() { ++openCalls; return true; }
};

struct SchedulerInput {
    int recoveryMode;
    bool continueAfterHedge;
    int recoveryState;
    bool recoveryMutatedThisTick;
    int overlapState;
    bool executionPending;
    bool spacingDue;
};

// Independent scheduler-integration oracle. It deliberately owns no strategy
// implementation details: every admission boundary is explicit and the spy
// proves whether the final broker-open seam was reached.
static bool drive_core_dca_once(const SchedulerInput &in, ExecutionSpy &exec)
{
    if(in.recoveryMutatedThisTick) return false;
    if(!recovery_core_growth_allows(in.recoveryMode,
                                    in.continueAfterHedge,
                                    in.recoveryState)) return false;
    if(overlap_blocks_core_growth(in.overlapState)) return false;
    if(in.executionPending || !in.spacingDue) return false;
    return exec.openMarket();
}

int main()
{
    int pass=0, fail=0;
    auto ck=[&](bool ok,const std::string &name){ if(ok) ++pass; else { ++fail; std::cerr << "FAIL: " << name << "\n"; } };

    // Owner counterexample from 20260827.log / tester screenshot.
    ck(buy_dca_due(4091.635, 4049.197, 13.0, 0.10),
       "11-BUY counterexample: DCA #12 is far beyond 13-pip spacing");

    // Recovery read-only ownership must not freeze Core growth when owner enabled continuation.
    ck(recovery_core_growth_allows(R_ACTIVE,true,R_HEDGE_BUILDING),
       "ContinueDca allows Core growth while Hedge Pyramid BUILDING waits");
    ck(recovery_core_growth_allows(R_ACTIVE,true,R_HEDGE_ACTIVE),
       "ContinueDca allows Core growth while Hedge ACTIVE waits");
    ck(recovery_core_growth_allows(R_ACTIVE,true,R_HEDGE_LOCKED),
       "ContinueDca allows Core growth while Hedge LOCKED");
    ck(recovery_core_growth_allows(R_ACTIVE,true,R_REHEDGE_PENDING),
       "ContinueDca allows Core growth while REHEDGE_PENDING");
    ck(!recovery_core_growth_allows(R_ACTIVE,false,R_HEDGE_BUILDING),
       "ContinueDca=false preserves Recovery Core-growth block");
    ck(!recovery_core_growth_allows(R_ACTIVE,true,R_HEDGE_TP_PENDING),
       "broker-close pending remains fail-closed");
    ck(!recovery_core_growth_allows(R_ACTIVE,true,R_RECONCILE_REQUIRED),
       "Recovery reconcile remains fail-closed");

    // Overlap read-only states do not own the side. Only actual broker mutation/reconcile does.
    ck(!overlap_blocks_core_growth(O_PAIR_ARMED),
       "PAIR_ARMED no longer blocks same-side DCA/Core Pyramid ADD");
    ck(!overlap_blocks_core_growth(O_LEG1_CONFIRMED),
       "broker-confirmed read-only state yields Core growth");
    ck(!overlap_blocks_core_growth(O_LEG2_RECHECK),
       "leg2 read-only recheck yields Core growth");
    ck(!overlap_blocks_core_growth(O_LEG2_WAIT_SAFE),
       "leg2 economic WAIT yields Core growth");
    ck(overlap_blocks_core_growth(O_LEG1_SUBMITTED),
       "leg1 broker request in-flight blocks Core growth");
    ck(overlap_blocks_core_growth(O_LEG2_SUBMITTED),
       "leg2 broker request in-flight blocks Core growth");
    ck(overlap_blocks_core_growth(O_RECONCILE),
       "ambiguous Overlap reconciliation blocks Core growth");

    // Do not durably commit a pair merely to wait for Recovery/economics.
    ck(!overlap_may_commit_pair(false,false), "unsafe economics remains soft candidate");
    ck(!overlap_may_commit_pair(true,true), "Recovery DEFER remains soft candidate");
    ck(overlap_may_commit_pair(true,false), "pair commits only when leg1 is executable");

    // Core growth changes the denominator; Recovery target must rebase upward from live Core units.
    long oldTarget = percent_units(26,120.0);
    long newTarget = percent_units(33,120.0);
    ck(newTarget > oldTarget && oldTarget == 31 && newTarget == 39,
       "Core DCA growth forces live Hedge target rebase");

    // Stateful admission proof for the exact owner 11-BUY counterexample.
    SchedulerInput case11{R_ACTIVE, true, R_HEDGE_BUILDING, false,
                          O_PAIR_ARMED, false,
                          buy_dca_due(4091.635, 4049.197, 13.0, 0.10)};
    ExecutionSpy case11Exec;
    ck(drive_core_dca_once(case11, case11Exec),
       "11-BUY traverses Recovery/Overlap/pending/spacing gates to execution seam");
    ck(case11Exec.openCalls == 1,
       "11-BUY integration submits exactly one broker-open intent");

    SchedulerInput mutating = case11;
    mutating.recoveryMutatedThisTick = true;
    ExecutionSpy mutatingExec;
    ck(!drive_core_dca_once(mutating, mutatingExec) && mutatingExec.openCalls == 0,
       "one-mutation-per-tick blocks concurrent Core DCA execution");

    SchedulerInput overlapSubmitted = case11;
    overlapSubmitted.overlapState = O_LEG1_SUBMITTED;
    ExecutionSpy overlapExec;
    ck(!drive_core_dca_once(overlapSubmitted, overlapExec) && overlapExec.openCalls == 0,
       "in-flight Overlap broker mutation blocks Core DCA execution");

    SchedulerInput optedOut = case11;
    optedOut.continueAfterHedge = false;
    ExecutionSpy optedOutExec;
    ck(!drive_core_dca_once(optedOut, optedOutExec) && optedOutExec.openCalls == 0,
       "owner continuation opt-out blocks the 11-BUY execution seam");

    std::cout << "T17.13 concurrency model: " << pass << " passed, " << fail << " failed\n";
    if(fail==0) std::cout << "ALL GREEN\n";
    return fail==0 ? 0 : 1;
}
