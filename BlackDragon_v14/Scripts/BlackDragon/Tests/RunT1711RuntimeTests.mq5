//+------------------------------------------------------------------+
//| RunT1711RuntimeTests.mq5 — T17.11 liveness/admission locks       |
//+------------------------------------------------------------------+
#property script_show_inputs
#include <BlackDragon/Recovery/RecoveryDca.mqh>
#include <BlackDragon/Recovery/RecoveryT177MigrationPolicy.mqh>
#include <BlackDragon/StrategyT1711Admission.mqh>

int g_t1711_pass=0,g_t1711_fail=0;
void T1711Check(const string name,const bool ok)
{
   if(ok){g_t1711_pass++;return;}
   g_t1711_fail++; Print("FAIL: ",name);
}

void OnStart()
{
   // R11-01: a stable ACTIVE/no-TP snapshot is read-only; semantic deltas
   // remain persistable before the scheduler considers the opposite side.
   T1711Check("snapshot stable",!Recovery_T1711ActiveTpSnapshotChangedPure(100,100,100,1.25,1.25,1.20,1.20));
   T1711Check("snapshot live delta",Recovery_T1711ActiveTpSnapshotChangedPure(90,100,100,1.25,1.25,1.20,1.20));
   T1711Check("snapshot remaining delta",Recovery_T1711ActiveTpSnapshotChangedPure(90,90,100,1.25,1.25,1.20,1.20));
   T1711Check("snapshot entry delta",Recovery_T1711ActiveTpSnapshotChangedPure(100,100,100,1.26,1.25,1.20,1.20));
   T1711Check("snapshot BE delta",Recovery_T1711ActiveTpSnapshotChangedPure(100,100,100,1.25,1.25,1.21,1.20));

   // R11-02: terminal-no-Hedge is an explicit authoritative topology. Both
   // DCA and CORE_ONLY Overlap consume the same terminal truth; ordinary
   // post-Hedge states continue to fail closed when live Hedge is absent.
   T1711Check("terminal no hedge",Recovery_T1711TerminalNoHedgePure(3,3,100,0,true));
   T1711Check("not terminal phase",!Recovery_T1711TerminalNoHedgePure(3,3,100,0,false));
   T1711Check("generation not maxed",!Recovery_T1711TerminalNoHedgePure(2,3,100,0,true));
   T1711Check("live hedge remains",!Recovery_T1711TerminalNoHedgePure(3,3,100,10,true));
   T1711Check("flat core rejected",!Recovery_T1711TerminalNoHedgePure(3,3,0,0,true));
   T1711Check("terminal DCA and Overlap continue",
              Recovery_T1711TerminalNoHedgeDcaAllowsPure(recovery_ACTIVE,true,true) &&
              !Recovery_T1711OverlapCoreOnlyBlockedPure(recovery_HEDGE_LOCKED,0.0,true,true));
   T1711Check("terminal opt-out blocks DCA and Overlap",
              !Recovery_T1711TerminalNoHedgeDcaAllowsPure(recovery_ACTIVE,false,true) &&
              Recovery_T1711OverlapCoreOnlyBlockedPure(recovery_HEDGE_LOCKED,0.0,true,false));
   T1711Check("nonterminal DCA and Overlap unchanged",
              !Recovery_T1711TerminalNoHedgeDcaAllowsPure(recovery_ACTIVE,true,false) &&
              Recovery_T1711OverlapCoreOnlyBlockedPure(recovery_HEDGE_LOCKED,0.0,false,true));

   // R11-03: the authoritative composition accepts the shipped defaults and
   // each formerly omitted family still fails its own invalid values.
   string why="";
   T1711Check("complete default config",Recovery_ValidateCompleteConfig((long)Magic,ACCOUNT_MARGIN_MODE_RETAIL_HEDGING,why));
   T1711Check("T5 invalid partial",!Recovery_ValidateT5Config(recovery_ACTIVE,10.0,101.0,recovery_Oldest,why));
   T1711Check("T6 invalid generations",!Recovery_ValidateT6Config(recovery_ACTIVE,1.0,0.0,1.0,0,why));
   T1711Check("DCA invalid coverage",!Recovery_ValidateDcaConfig(recovery_ACTIVE,-1.0,0.0,why));

   // R11-04: only NO_MONEY is a capacity block. Transient transport errors
   // retain existing retry/reconcile semantics and successful admission clears.
   T1711Check("submit accepted",Exec_SubmitDispositionPure(true,TRADE_RETCODE_DONE)==EXEC_SUBMIT_ACCEPTED);
   T1711Check("NO_MONEY capacity",Exec_SubmitDispositionPure(false,TRADE_RETCODE_NO_MONEY)==EXEC_SUBMIT_CAPACITY_BLOCKED);
   T1711Check("timeout transient",Exec_SubmitDispositionPure(false,TRADE_RETCODE_TIMEOUT)==EXEC_SUBMIT_TRANSIENT);
   T1711Check("invalid rejected",Exec_SubmitDispositionPure(false,TRADE_RETCODE_INVALID)==EXEC_SUBMIT_REJECTED);

   SCoreCapacityLatch latch;
   Strategy_T1711ResetCapacityLatch(latch);
   T1711Check("inactive allows",!Recovery_T1711CapacityLatchBlocksPure(latch,BD_DIR_BUY,3,0.30,1000,50.0,0.01));
   SExecSubmitOutcome outcome; ZeroMemory(outcome);
   outcome.disposition=EXEC_SUBMIT_CAPACITY_BLOCKED;
   outcome.normalizedVolume=0.30;
   outcome.requiredMargin=100.0;
   Strategy_T1711LatchCapacity(latch,BD_DIR_BUY,3,1000,outcome);
   T1711Check("same intent blocks",Recovery_T1711CapacityLatchBlocksPure(latch,BD_DIR_BUY,3,0.30,1000,50.0,0.01));
   T1711Check("other direction allows",!Recovery_T1711CapacityLatchBlocksPure(latch,BD_DIR_SELL,3,0.30,1000,50.0,0.01));
   T1711Check("other index allows",!Recovery_T1711CapacityLatchBlocksPure(latch,BD_DIR_BUY,4,0.30,1000,50.0,0.01));
   T1711Check("smaller volume allows",!Recovery_T1711CapacityLatchBlocksPure(latch,BD_DIR_BUY,3,0.20,1000,50.0,0.01));
   T1711Check("larger volume distinct",!Recovery_T1711CapacityLatchBlocksPure(latch,BD_DIR_BUY,3,0.40,1000,50.0,0.01));
   T1711Check("new bar allows",!Recovery_T1711CapacityLatchBlocksPure(latch,BD_DIR_BUY,3,0.30,1060,50.0,0.01));
   T1711Check("margin recovery allows",!Recovery_T1711CapacityLatchBlocksPure(latch,BD_DIR_BUY,3,0.30,1000,100.0,0.01));
   Strategy_T1711ResetCapacityLatch(latch);
   T1711Check("reset clears",!latch.active && latch.direction==-1 && latch.dcaIndex==0);

   Print("T17.11 runtime tests: ",g_t1711_pass," passed, ",g_t1711_fail," failed");
   if(g_t1711_fail==0) Print("ALL GREEN"); else Print("TESTS FAILED");
}
