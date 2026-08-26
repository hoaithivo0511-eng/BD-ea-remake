#include <cmath>
#include <iostream>

enum Phase { IDLE=0, ARMED, BUILDING, ACTIVE, TP_PENDING, CORE_FUNDING,
             LOCK_PENDING, PROTECTIVE_WAIT, LOCKED, GLOBAL_PROTECT };
enum Submit { REJECTED=0, ACCEPTED, TRANSIENT, CAPACITY_BLOCKED };

struct Latch {
    bool active=false;
    int dir=0;
    int index=0;
    double volume=0;
    long bar=0;
    double requiredMargin=0;
};
struct SideWork { bool passive=false; bool actionable=false; };

bool snapshot_changed(long live,long opened,long remaining,double be,double storedBe) {
    return live!=opened || live!=remaining || std::fabs(be-storedBe)>1e-12;
}
bool terminal_no_hedge(Phase phase,int generation,int maxGeneration,long core,long hedge) {
    return phase==LOCKED && maxGeneration>=1 && generation>=maxGeneration && core>0 && hedge<=0;
}
bool dca_metrics_required(bool postHedgeStable,bool terminalNoHedge,bool coverageOn,bool corridorOn) {
    return postHedgeStable && !terminalNoHedge && (coverageOn||corridorOn);
}
int scheduler_actions(const SideWork& buy,const SideWork& sell) {
    int actions=0;
    // A passive wait is side-local: it suppresses only that side's mutation.
    if(!buy.passive && buy.actionable) ++actions;
    if(!sell.passive && sell.actionable) ++actions;
    return actions;
}
Submit classify_submit(bool accepted,unsigned rc) {
    if(accepted) return ACCEPTED;
    if(rc==10019) return CAPACITY_BLOCKED; // TRADE_RETCODE_NO_MONEY
    if(rc==10004 || rc==10020 || rc==10021 || rc==10012 || rc==10031) return TRANSIENT;
    return REJECTED;
}
bool latch_blocks(const Latch& l,int dir,int index,double volume,long bar,double freeMargin,double step) {
    if(!l.active) return false;
    double eps=step>0 ? step*0.25 : 1e-12;
    if(dir!=l.dir || index!=l.index) return false;
    if(std::fabs(volume-l.volume)>eps) return false;
    if(bar!=l.bar) return false;
    if(l.requiredMargin>0 && freeMargin+1e-9>=l.requiredMargin) return false;
    return true;
}

int main() {
    int pass=0,fail=0;
    auto ck=[&](const char* n,bool ok){if(ok)++pass;else{++fail;std::cerr<<"FAIL "<<n<<"\n";}};

    ck("stable snapshot unchanged",!snapshot_changed(70,70,70,4081.2,4081.2));
    ck("fill delta persists",snapshot_changed(71,70,70,4081.2,4081.2));
    ck("BE delta persists",snapshot_changed(70,70,70,4081.3,4081.2));
    ck("passive BUY cannot own SELL",scheduler_actions({true,false},{false,true})==1);
    ck("both passive no mutation",scheduler_actions({true,false},{true,false})==0);

    ck("terminal exact max",terminal_no_hedge(LOCKED,5,5,100,0));
    ck("terminal over max",terminal_no_hedge(LOCKED,6,5,100,0));
    ck("premax not terminal",!terminal_no_hedge(LOCKED,4,5,100,0));
    ck("active missing hedge not terminal",!terminal_no_hedge(ACTIVE,5,5,100,0));
    ck("no core not terminal",!terminal_no_hedge(LOCKED,5,5,0,0));
    ck("live hedge not terminal",!terminal_no_hedge(LOCKED,5,5,100,1));
    ck("terminal bypasses N-A metrics",!dca_metrics_required(true,true,true,true));
    ck("ordinary locked still needs metrics",dca_metrics_required(true,false,true,true));

    ck("accepted disposition",classify_submit(true,10009)==ACCEPTED);
    ck("NO_MONEY capacity",classify_submit(false,10019)==CAPACITY_BLOCKED);
    ck("requote transient",classify_submit(false,10004)==TRANSIENT);
    ck("price changed transient",classify_submit(false,10020)==TRANSIENT);
    ck("invalid rejected",classify_submit(false,10013)==REJECTED);

    Latch buy{true,0,6,.24,1000,250};
    ck("same bar same payload blocked",latch_blocks(buy,0,6,.24,1000,100,.01));
    ck("next bar released",!latch_blocks(buy,0,6,.24,1060,100,.01));
    ck("smaller lot released",!latch_blocks(buy,0,6,.20,1000,100,.01));
    ck("new index released",!latch_blocks(buy,0,7,.24,1000,100,.01));
    ck("margin recovered released",!latch_blocks(buy,0,6,.24,1000,250,.01));
    ck("SELL independent",!latch_blocks(buy,1,6,.24,1000,100,.01));
    ck("inactive latch released",!latch_blocks(Latch{},0,6,.24,1000,100,.01));

    std::cout<<"T17.11 runtime model: "<<pass<<" passed, "<<fail<<" failed\n";
    if(fail==0)std::cout<<"ALL GREEN\n";
    return fail==0?0:1;
}
