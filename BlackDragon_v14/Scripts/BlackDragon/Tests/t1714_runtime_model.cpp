#include <iostream>
#include <numeric>
#include <string>
#include <vector>

enum Refresh { UNCHANGED=0, APPLY=1, RECONCILE=2 };
enum Guard { NONE=0, ACCOUNT=1, MAGIC=2, BUY=3, SELL=4, DAILY=5 };

static Refresh classify_refresh(long persisted, long live, long proven)
{
    if(persisted < 0 || live < 0 || live > persisted || proven < 0)
        return RECONCILE;
    long observed = persisted - live;
    if(observed == 0) return UNCHANGED;
    return proven == observed ? APPLY : RECONCILE;
}

static bool account_preempts_recovery(Guard guard, bool recoveryBlocking)
{
    return recoveryBlocking && guard == ACCOUNT;
}

int main()
{
    int pass=0, fail=0;
    auto ck=[&](bool ok,const std::string &name){
        if(ok) ++pass; else { ++fail; std::cerr << "FAIL: " << name << "\n"; }
    };

    // Exact owner runtime batch: 12 broker-SL deals close 1.34 lots at 0.01 step.
    const std::vector<long> slUnits{5,2,2,18,6,11,9,11,10,17,17,26};
    const long proven=std::accumulate(slUnits.begin(),slUnits.end(),0L);
    ck(slUnits.size()==12 && proven==134,
       "runtime oracle contains twelve exact protective closes totaling 134 units");
    ck(classify_refresh(134,0,proven)==APPLY,
       "finalizer-before-callback applies exact proven 134-unit decrease");
    ck(classify_refresh(0,0,proven)==UNCHANGED,
       "duplicate callback or refresh is ownership-idempotent");
    ck(classify_refresh(134,0,133)==RECONCILE,
       "partial protective proof remains fail-closed");
    ck(classify_refresh(134,0,135)==RECONCILE,
       "over-counted protective proof remains fail-closed");
    ck(classify_refresh(134,135,0)==RECONCILE,
       "unexpected live-volume increase remains fail-closed");
    ck(classify_refresh(134,134,0)==UNCHANGED,
       "unchanged broker exposure needs no ownership mutation");

    ck(account_preempts_recovery(ACCOUNT,true),
       "account MoneyGuard preempts Recovery reconcile hold");
    ck(!account_preempts_recovery(BUY,true),
       "BUY MoneyGuard preserves side coordinator semantics");
    ck(!account_preempts_recovery(MAGIC,true),
       "MAGIC MoneyGuard preserves scoped coordinator semantics");
    ck(!account_preempts_recovery(ACCOUNT,false),
       "account preemption is unnecessary when Recovery is idle");

    // Idempotent begin oracle: repeated guard ticks do not reset the active epoch.
    bool accountPending=false;
    int beginEpochs=0;
    auto begin=[&](){ if(!accountPending){ accountPending=true; ++beginEpochs; } };
    begin(); begin(); begin();
    ck(accountPending && beginEpochs==1,
       "repeated account guard ticks begin exactly one global-flatten epoch");

    std::cout << "T17.14 runtime model: " << pass << " passed, " << fail << " failed\n";
    if(fail==0) std::cout << "ALL GREEN\n";
    return fail==0 ? 0 : 1;
}
