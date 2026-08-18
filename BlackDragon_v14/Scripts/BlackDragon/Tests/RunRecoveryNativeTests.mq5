//+------------------------------------------------------------------+
//| RunRecoveryNativeTests.mq5 — Adaptive Recovery T3-T9 native      |
//| Executes deterministic Recovery rules inside real MQL5 runtime.  |
//| No trade requests are sent and no live trading is enabled.       |
//+------------------------------------------------------------------+
#property script_show_inputs

#include <BlackDragon/Recovery/RecoveryPersistence.mqh>
#include <BlackDragon/Recovery/RecoveryDca.mqh>
#include <BlackDragon/Recovery/RecoveryLock.mqh>

int g_pass = 0;
int g_fail = 0;

void Check(const string name, const bool cond)
{
   if(cond) { g_pass++; return; }
   g_fail++;
   Print("FAIL: ", name);
}

void CheckEq(const string name, const double got, const double want, const double eps=1e-9)
{
   Check(name, MathAbs(got-want) <= eps);
}

void CheckLong(const string name, const long got, const long want)
{
   Check(name, got == want);
}

void OnStart()
{
   // T3 — FSM, activation gap, coverage and corridor ---------------------
   Check("T3 CORE_ONLY->ARMED", Recovery_StateTransitionAllowed(recovery_CORE_ONLY, recovery_ARMED));
   Check("T3 CORE_ONLY !->HEDGE_ACTIVE", !Recovery_StateTransitionAllowed(recovery_CORE_ONLY, recovery_HEDGE_ACTIVE));
   Check("T3 HEDGE_BUILDING->HEDGE_ACTIVE", Recovery_StateTransitionAllowed(recovery_HEDGE_BUILDING, recovery_HEDGE_ACTIVE));
   Check("T3 HEDGE_ACTIVE->TP_PENDING", Recovery_StateTransitionAllowed(recovery_HEDGE_ACTIVE, recovery_HEDGE_TP_PENDING));
   Check("T3 GLOBAL_STOP->COMPLETED", Recovery_StateTransitionAllowed(recovery_GLOBAL_STOP, recovery_COMPLETED));
   Check("T3 GLOBAL_STOP terminal otherwise", !Recovery_StateTransitionAllowed(recovery_GLOBAL_STOP, recovery_ARMED));
   Check("T3 COMPLETED->CORE_ONLY", Recovery_StateTransitionAllowed(recovery_COMPLETED, recovery_CORE_ONLY));
   Check("T3 no self transition", !Recovery_StateTransitionAllowed(recovery_ARMED, recovery_ARMED));

   Check("T3 BUY adverse boundary", Recovery_AdverseGapHitTicks(recovery_CORE_BUY,1000,950,951,50));
   Check("T3 BUY before boundary false", !Recovery_AdverseGapHitTicks(recovery_CORE_BUY,1000,951,952,50));
   Check("T3 SELL adverse boundary", Recovery_AdverseGapHitTicks(recovery_CORE_SELL,1000,1049,1050,50));
   Check("T3 SELL before boundary false", !Recovery_AdverseGapHitTicks(recovery_CORE_SELL,1000,1048,1049,50));
   Check("T3 zero gap immediate", Recovery_AdverseGapHitTicks(recovery_CORE_BUY,1000,1000,1001,0));

   CheckEq("T3 coverage 50%", Recovery_CoveragePercent(1.0,0.5),50.0);
   CheckEq("T3 zero core coverage", Recovery_CoveragePercent(0.0,0.5),0.0);
   CheckEq("T3 BUY corridor +50", Recovery_CorridorPrice(recovery_CORE_BUY,1900.0,1950.0),50.0);
   CheckEq("T3 SELL corridor +50", Recovery_CorridorPrice(recovery_CORE_SELL,2000.0,1950.0),50.0);
   CheckLong("T3 BUY Core hedge is SELL", Recovery_HedgeDirection(recovery_CORE_BUY),1);
   CheckLong("T3 SELL Core hedge is BUY", Recovery_HedgeDirection(recovery_CORE_SELL),0);

   // T4 — exact smart split and exposure-deficit sizing -----------------
   Check("T4 no volume limit", Recovery_VolumeLimitAllows(100,500,0));
   Check("T4 volume limit exact", Recovery_VolumeLimitAllows(40,60,100));
   Check("T4 volume limit overflow blocked", !Recovery_VolumeLimitAllows(41,60,100));
   CheckLong("T4 one child exact max", Recovery_BundleNextChildUnits(100,10,100),100);
   CheckLong("T4 max+min child", Recovery_BundleNextChildUnits(110,10,100),100);
   CheckLong("T4 avoid below-min residual", Recovery_BundleNextChildUnits(105,10,100),95);
   CheckLong("T4 below minimum impossible", Recovery_BundleNextChildUnits(5,10,100),0);

   long children[];
   string why = "";
   Check("T4 plan 250", Recovery_BuildBundlePlan(250,10,100,0,0,children,why));
   CheckLong("T4 plan 250 child count", ArraySize(children),3);
   if(ArraySize(children)==3)
   {
      CheckLong("T4 plan 250 child1",children[0],100);
      CheckLong("T4 plan 250 child2",children[1],100);
      CheckLong("T4 plan 250 child3",children[2],50);
   }
   Check("T4 plan 205 exact", Recovery_BuildBundlePlan(205,10,100,0,0,children,why));
   CheckLong("T4 plan 205 child count", ArraySize(children),3);
   if(ArraySize(children)==3)
   {
      CheckLong("T4 plan 205 child1",children[0],100);
      CheckLong("T4 plan 205 child2",children[1],95);
      CheckLong("T4 plan 205 child3",children[2],10);
   }
   Check("T4 unrepresentable target blocked", !Recovery_BuildBundlePlan(5,10,100,0,0,children,why));
   CheckLong("T4 rehedge deficit 60", Recovery_RehedgeRequiredUnits(100,40),60);
   CheckLong("T4 rehedge no hedge -> full core", Recovery_RehedgeRequiredUnits(100,0),100);
   CheckLong("T4 rehedge fully covered -> 0", Recovery_RehedgeRequiredUnits(100,100),0);
   CheckLong("T4 confirmed delta", Recovery_BundleConfirmedNewUnits(90,40),50);
   CheckEq("T4 bundle coverage 50", Recovery_BundleCoveragePercent(50,100),50.0);

   // T5 — realized ledger, virtual TP, partial close and allocation ------
   CheckEq("T5 deal cash exact", Recovery_DealCashPure(10.0,-1.0,-0.5,-0.2),8.3,1e-9);
   SRecoveryRealizedLedger ledger;
   Recovery_LedgerInit(ledger);
   Recovery_LedgerApplyHedgeDeal(ledger,20.0,50);
   CheckEq("T5 hedge credit 20", ledger.availableCredit,20.0);
   CheckLong("T5 hedge realized units 50", ledger.hedgeRealizedCloseUnits,50);
   Recovery_LedgerApplyCoreDeal(ledger,-7.0);
   CheckEq("T5 spend leaves 13", ledger.availableCredit,13.0);
   Check("T5 no deficit within credit", !ledger.deficit);
   Recovery_LedgerApplyCoreDeal(ledger,-20.0);
   CheckEq("T5 over-spend clamps credit 0", ledger.availableCredit,0.0);
   Check("T5 over-spend flags deficit", ledger.deficit);

   CheckEq("T5 BUY hedge netBE cost shift", Recovery_NetBreakevenFromCosts(100.0,1.0,-2.0,1.0,0.1,true),100.2,1e-9);
   CheckEq("T5 SELL hedge netBE cost shift", Recovery_NetBreakevenFromCosts(100.0,1.0,-2.0,1.0,0.1,false),99.8,1e-9);
   Check("T5 SELL hedge virtual TP boundary", Recovery_VirtualHedgeTpHit(recovery_CORE_BUY,100.0,94.9,95.0,5.0));
   Check("T5 SELL hedge virtual TP before false", !Recovery_VirtualHedgeTpHit(recovery_CORE_BUY,100.0,94.91,95.01,5.0));
   Check("T5 BUY hedge virtual TP boundary", Recovery_VirtualHedgeTpHit(recovery_CORE_SELL,100.0,105.0,105.1,5.0));

   CheckLong("T5 50% partial", Recovery_PartialCloseTargetUnits(100,50.0,1),50);
   CheckLong("T5 below min partial blocked", Recovery_PartialCloseTargetUnits(10,50.0,6),0);
   CheckLong("T5 residual min protection", Recovery_PartialCloseTargetUnits(20,75.0,10),10);
   CheckLong("T5 legal full close", Recovery_LegalCloseUnits(20,20,10),20);
   CheckLong("T5 legal close reduces to protect residual", Recovery_LegalCloseUnits(15,20,10),10);
   CheckLong("T5 sub-min close blocked", Recovery_LegalCloseUnits(5,20,10),0);

   SRecoveryCloseCandidate hedgeCandidates[];
   ArrayResize(hedgeCandidates,2);
   hedgeCandidates[0].ticket=101; hedgeCandidates[0].openTime=1; hedgeCandidates[0].units=60; hedgeCandidates[0].floatingCash=0.0;
   hedgeCandidates[1].ticket=102; hedgeCandidates[1].openTime=2; hedgeCandidates[1].units=40; hedgeCandidates[1].floatingCash=0.0;
   SRecoveryCloseAction hedgeActions[];
   Check("T5 hedge close plan exact 70", Recovery_BuildHedgeClosePlan(hedgeCandidates,70,10,hedgeActions,why));
   CheckLong("T5 hedge close plan action count",ArraySize(hedgeActions),2);
   if(ArraySize(hedgeActions)==2)
   {
      CheckLong("T5 hedge close first full",hedgeActions[0].units,60);
      CheckLong("T5 hedge close second partial",hedgeActions[1].units,10);
   }

   SRecoveryCloseCandidate coreCandidates[];
   ArrayResize(coreCandidates,2);
   coreCandidates[0].ticket=201; coreCandidates[0].openTime=1; coreCandidates[0].units=100; coreCandidates[0].floatingCash=-100.0;
   coreCandidates[1].ticket=202; coreCandidates[1].openTime=2; coreCandidates[1].units=100; coreCandidates[1].floatingCash=-100.0;
   SRecoveryCloseAction coreActions[];
   double estimatedLoss=0.0;
   Check("T5 pro-rata plan", Recovery_BuildCoreClosePlan(coreCandidates,recovery_ProRata,100.0,1,coreActions,estimatedLoss,why));
   CheckLong("T5 pro-rata two tickets",ArraySize(coreActions),2);
   CheckEq("T5 pro-rata consumes 100",estimatedLoss,100.0,1e-8);
   if(ArraySize(coreActions)==2)
   {
      CheckLong("T5 pro-rata first 50",coreActions[0].units,50);
      CheckLong("T5 pro-rata second 50",coreActions[1].units,50);
   }

   // T6 — lock geometry, generation bounds and re-hedge anchor ------------
   CheckEq("T6 SELL-hedge lock floor", Recovery_NormalizeLockPricePure(recovery_CORE_BUY,99.56,0.1,1),99.5,1e-9);
   CheckEq("T6 BUY-hedge lock ceil", Recovery_NormalizeLockPricePure(recovery_CORE_SELL,100.44,0.1,1),100.5,1e-9);
   CheckEq("T6 SELL-hedge target", Recovery_LockTargetPricePure(recovery_CORE_BUY,100.0,99.8,0.5,0.1,0.1,1),99.5,1e-9);
   CheckEq("T6 BUY-hedge target", Recovery_LockTargetPricePure(recovery_CORE_SELL,100.0,100.2,0.5,0.1,0.1,1),100.5,1e-9);
   Check("T6 stronger SELL-hedge SL satisfied", Recovery_LockSatisfiedPure(recovery_CORE_BUY,99.4,99.5,0.1));
   Check("T6 weaker SELL-hedge SL not satisfied", !Recovery_LockSatisfiedPure(recovery_CORE_BUY,99.7,99.5,0.1));
   Check("T6 stronger BUY-hedge SL satisfied", Recovery_LockSatisfiedPure(recovery_CORE_SELL,100.6,100.5,0.1));
   Check("T6 broker distance SELL hedge valid", Recovery_LockBrokerDistanceValidPure(recovery_CORE_BUY,95.0,89.0,90.0,1.0,2,1,0.1));
   Check("T6 broker distance SELL hedge reject", !Recovery_LockBrokerDistanceValidPure(recovery_CORE_BUY,91.0,89.0,90.0,1.0,2,1,0.1));
   Check("T6 generation 1 may start", Recovery_GenerationCanStartPure(0,1));
   Check("T6 Max+1 blocked", !Recovery_GenerationCanStartPure(1,1));
   Check("T6 invalid negative generation blocked", !Recovery_GenerationCanStartPure(-1,5));
   CheckLong("T6 weighted anchor ticks", Recovery_WeightedAnchorTicksPure(2000.0,20,0.1),1000);

   // T7 — Continue-DCA, coverage and corridor gates ----------------------
   Check("T7 OFF is legacy pass-through", Recovery_DcaStateAllows(recovery_OFF,false,recovery_HEDGE_BUILDING));
   Check("T7 ACTIVE CORE_ONLY allowed", Recovery_DcaStateAllows(recovery_ACTIVE,false,recovery_CORE_ONLY));
   Check("T7 ACTIVE ARMED allowed", Recovery_DcaStateAllows(recovery_ACTIVE,false,recovery_ARMED));
   Check("T7 active hedge blocked when ContinueDCA off", !Recovery_DcaStateAllows(recovery_ACTIVE,false,recovery_HEDGE_ACTIVE));
   Check("T7 active hedge allowed when ContinueDCA on", Recovery_DcaStateAllows(recovery_ACTIVE,true,recovery_HEDGE_ACTIVE));
   Check("T7 building always blocked", !Recovery_DcaStateAllows(recovery_ACTIVE,true,recovery_HEDGE_BUILDING));
   Check("T7 coverage exact boundary", Recovery_DcaCoverageAllows(80.0,1.0,0.8));
   Check("T7 coverage below boundary blocked", !Recovery_DcaCoverageAllows(80.0,1.0,0.79));
   Check("T7 coverage zero disables", Recovery_DcaCoverageAllows(0.0,1.0,0.0));
   Check("T7 corridor exact target stops DCA", !Recovery_DcaCorridorAllows(10.0,recovery_CORE_BUY,100.0,110.0,1.0));
   Check("T7 corridor below target allows DCA", Recovery_DcaCorridorAllows(11.0,recovery_CORE_BUY,100.0,110.0,1.0));
   Check("T7 negative corridor does not block", Recovery_DcaCorridorAllows(10.0,recovery_CORE_BUY,110.0,100.0,1.0));

   // T9 — persistence identity helpers and pending effect dedupe ----------
   uchar empty[];
   CheckLong("T9 FNV empty", (long)Recovery_Fnv1aBytes(empty),2166136261);
   uchar one[];
   ArrayResize(one,1); one[0]=0x61;
   CheckLong("T9 FNV 'a'", (long)Recovery_Fnv1aBytes(one),3826002220);
   CheckLong("T9 UTF16 string hash A", (long)Recovery_StringHash("A"),1792377636);
   Check("T9 safe file token", Recovery_SafeFileToken("XAU/USD") == "XAU_USD");
   Check("T9 empty file token", Recovery_SafeFileToken("") == "symbol");
   Check("T9 valid state", Recovery_PersistStateValueValid(recovery_HEDGE_ACTIVE));
   Check("T9 invalid low state", !Recovery_PersistStateValueValid((eRecoveryState)-1));
   Check("T9 OPEN effect exact", Recovery_PendingVolumeEffectConfirmed(true,10,5,15));
   Check("T9 OPEN effect incomplete", !Recovery_PendingVolumeEffectConfirmed(true,10,5,14));
   Check("T9 CLOSE effect exact", Recovery_PendingVolumeEffectConfirmed(false,10,5,5));
   Check("T9 CLOSE effect incomplete", !Recovery_PendingVolumeEffectConfirmed(false,10,5,6));
   Check("T9 CLOSE full-to-zero", Recovery_PendingVolumeEffectConfirmed(false,10,20,0));

   PrintFormat("Adaptive Recovery native tests: %d passed, %d failed",g_pass,g_fail);
   if(g_fail==0) Print("ALL GREEN — Adaptive Recovery T3-T9 deterministic MQL5 behavior passed.");
}
