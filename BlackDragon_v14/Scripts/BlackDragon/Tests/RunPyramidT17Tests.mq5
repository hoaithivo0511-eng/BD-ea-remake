//+------------------------------------------------------------------+
//| RunPyramidT17Tests.mq5 — T17.3 native pure-policy tests          |
//+------------------------------------------------------------------+
#property script_show_inputs
#include <BlackDragon/Pyramid/PyramidConfig.mqh>
#include <BlackDragon/MoneyGuard.mqh>
#include <BlackDragon/Recovery/RecoveryT16Config.mqh>

int g_pass=0, g_fail=0;
void Check(const string name,const bool cond){if(cond){g_pass++;return;}g_fail++;Print("FAIL: ",name);}
bool Near(const double a,const double b,const double eps=1e-9){return MathAbs(a-b)<=eps;}

void OnStart()
{
   Check("BUY favorable hit", Pyramid_FavorableGapHitPure(0,4000.0,4000.9,4001.0,1.0));
   Check("BUY favorable miss", !Pyramid_FavorableGapHitPure(0,4000.0,4000.8,4000.9,1.0));
   Check("SELL favorable hit", Pyramid_FavorableGapHitPure(1,4000.0,3999.0,3999.1,1.0));
   Check("SELL favorable miss", !Pyramid_FavorableGapHitPure(1,4000.0,3999.1,3999.2,1.0));
   Check("BUY LIFO peel hit", Pyramid_PeelHitPure(0,4001.0,4000.3,4000.4,0.7));
   Check("BUY LIFO peel miss", !Pyramid_PeelHitPure(0,4001.0,4000.31,4000.41,0.7));
   Check("SELL LIFO peel hit", Pyramid_PeelHitPure(1,3999.0,3999.6,3999.7,0.7));
   Check("SELL LIFO peel miss", !Pyramid_PeelHitPure(1,3999.0,3999.59,3999.69,0.7));
   Check("BUY favorable pips", Near(Pyramid_FavorablePipsPure(0,4000.0,4001.0,4001.1,0.1),10.0));
   Check("SELL favorable pips", Near(Pyramid_FavorablePipsPure(1,4000.0,3998.9,3999.0,0.1),10.0));
   Check("BUY room to TP", Near(Pyramid_RoomToTpPipsPure(0,4002.0,4001.4,4001.5,0.1),5.0));
   Check("SELL room to TP", Near(Pyramid_RoomToTpPipsPure(1,3998.0,3998.5,3998.6,0.1),5.0));

   Check("legacy profit-funded cap", Near(Pyramid_RiskCapLotPure(20.0,30.0,100.0),0.06,1e-12));
   Check("legacy risk cap pct clamps 100", Near(Pyramid_RiskCapLotPure(20.0,150.0,100.0),0.20,1e-12));
   Check("legacy risk cap no profit zero", Pyramid_RiskCapLotPure(0.0,30.0,100.0)==0.0);
   Check("legacy risk cap no budget zero", Pyramid_RiskCapLotPure(20.0,0.0,100.0)==0.0);

   Check("coverage master cap", Pyramid_EffectiveCoveragePure(115.0,100.0,115.0)==100.0);
   Check("coverage hard cap", Pyramid_EffectiveCoveragePure(100.0,115.0,80.0)==80.0);
   Check("coverage unchanged", Pyramid_EffectiveCoveragePure(55.0,100.0,100.0)==55.0);
   Check("ARCS layered raw 35 pct", Recovery_T16NewGenerationRawUnitsPure(ARCS_XEP_LOP,100,0,35.0)==35);
   Check("balanced raw subtract existing", Recovery_T16NewGenerationRawUnitsPure(HEDGE_CAN_BANG,100,35,55.0)==20);
   Check("balanced already covered zero", Recovery_T16NewGenerationRawUnitsPure(HEDGE_CAN_BANG,100,60,55.0)==0);
   Check("broker minimum clamp", Recovery_T166ClampPositiveGenerationUnitsPure(1,2)==2);
   Check("zero never invents hedge", Recovery_T166ClampPositiveGenerationUnitsPure(0,2)==0);
   Check("runtime hard cap OFF preserves configured target",
         Near(Recovery_T17RuntimeHedgePercentPure(hedge_pyramid_TAT,115.0,115.0,75.0),115.0));
   Check("runtime hard cap ON caps configured target",
         Near(Recovery_T17RuntimeHedgePercentPure(hedge_pyramid_BAC_COVERAGE,115.0,115.0,75.0),75.0));
   Check("runtime hard cap leaves explicit stage percent unchanged",
         Near(Recovery_T17RuntimeHedgePercentPure(hedge_pyramid_BAC_COVERAGE,55.0,115.0,75.0),55.0));

   string c=Pyramid_BuildComment(0,4);
   Check("role comment level", Pyramid_LevelFromComment(c)==4);
   Check("non pyramid comment rejected", Pyramid_LevelFromComment("EA Black Dragon|4")==-1);

   Check("serial first", Pyramid_NextSerialLevelPure(0)==1);
   Check("serial exceeds old 32 cap", Pyramid_NextSerialLevelPure(32)==33);
   Check("serial can continue long trend", Pyramid_NextSerialLevelPure(100)==101);
   Check("concurrent 2 of 3 allowed", Pyramid_ConcurrentAddAllowedPure(2,3));
   Check("concurrent 3 of 3 blocked", !Pyramid_ConcurrentAddAllowedPure(3,3));
   Check("concurrent cap zero disables ADD", !Pyramid_ConcurrentAddAllowedPure(0,0));
   Check("historical 30 adds do not consume concurrent capacity", Pyramid_ConcurrentAddAllowedPure(0,3));
   Check("legacy live Pyramid anchor", Near(Pyramid_RearmAnchorPure(4020.0,3990.0),4020.0));
   Check("legacy no live Pyramid falls back BE", Near(Pyramid_RearmAnchorPure(0.0,3990.0),3990.0));

   Check("post Peel anchor is exit not old live P2",
         Near(Pyramid_T173RearmAnchorPure(4020.0,3990.0,90000,100000,120000,4030.0),4030.0));
   Check("DCA after Peel resets epoch anchor to current BE",
         Near(Pyramid_T173RearmAnchorPure(4020.0,3988.0,140000,100000,120000,4030.0),3988.0));
   Check("new Pyramid after DCA resumes live anchor",
         Near(Pyramid_T173RearmAnchorPure(4040.0,3988.0,140000,150000,120000,4030.0),4040.0));
   Check("post Peel old 4035 region no longer enough",
         !Pyramid_FavorableGapHitPure(0,4030.0,4034.9,4035.0,20.0));
   Check("post Peel fresh 20 gap can rearm",
         Pyramid_FavorableGapHitPure(0,4030.0,4049.9,4050.0,20.0));

   Check("same bar add blocked legacy", !Pyramid_AddTimingAllowsPure(100,100,110,100,0));
   Check("new bar delay disabled allowed legacy", Pyramid_AddTimingAllowsPure(100,100,160,120,0));
   Check("new bar but MinuteStop blocks legacy", !Pyramid_AddTimingAllowsPure(100,100,200,120,5));
   Check("new bar and MinuteStop passed legacy", Pyramid_AddTimingAllowsPure(100,100,401,120,5));
   Check("Peel mutation blocks same-bar refill",
         !Pyramid_T173AddAfterMutationAllowsPure(130,150,120,0));
   Check("later bar allows refill with delay off",
         Pyramid_T173AddAfterMutationAllowsPure(130,181,180,0));
   Check("later bar MinuteStop still blocks",
         !Pyramid_T173AddAfterMutationAllowsPure(130,200,180,5));
   Check("later bar MinuteStop passes",
         Pyramid_T173AddAfterMutationAllowsPure(130,431,420,5));

   Check("fixed lot ignores risk cap", !Pyramid_RiskBudgetAppliesPure(pyramid_LOT_CHUOI,30.0));
   Check("multiplier risk cap enabled", Pyramid_RiskBudgetAppliesPure(pyramid_LOT_HE_SO,30.0));
   Check("multiplier budget zero disables cap", !Pyramid_RiskBudgetAppliesPure(pyramid_LOT_HE_SO,0.0));
   Check("risk mode zero budget not ready", !Pyramid_RiskModeReadyPure(pyramid_LOT_RUI_RO,0.0));
   Check("risk mode positive budget ready", Pyramid_RiskModeReadyPure(pyramid_LOT_RUI_RO,30.0));

   Check("campaign economic includes realized loss", Near(Pyramid_CampaignEconomicProfitPure(100.0,-40.0),60.0));
   Check("campaign economic hidden loss", Near(Pyramid_CampaignEconomicProfitPure(300.0,-500.0),-200.0));
   Check("available risk subtracts realized loss", Near(Pyramid_AvailableRiskCashPure(100.0,-50.0,0.0,100.0),50.0));
   Check("available risk subtracts open Pyramid risk", Near(Pyramid_AvailableRiskCashPure(100.0,0.0,20.0,30.0),10.0));
   Check("available risk exhausted by realized loss", Pyramid_AvailableRiskCashPure(100.0,-100.0,0.0,100.0)==0.0);
   Check("available risk cannot go negative", Pyramid_AvailableRiskCashPure(100.0,0.0,40.0,30.0)==0.0);
   Check("economic min locked blocks negative campaign",
         !Pyramid_EconomicMinLockedAllowsPure(20.0,-80.0,5.0,0.10,1.0,0.01,0.1));
   Check("economic min locked allows funded campaign",
         Pyramid_EconomicMinLockedAllowsPure(100.0,-40.0,5.0,0.10,1.0,0.01,0.1));
   Check("economic min locked zero disables gate",
         Pyramid_EconomicMinLockedAllowsPure(-100.0,-100.0,0.0,0.10,1.0,0.01,0.1));

   Check("DCA priority releases Pyramid at full MaxOrders",
         Pyramid_DcaPriorityReleaseNeededPure(true,59,59,30));
   Check("DCA priority no release with free slot",
         !Pyramid_DcaPriorityReleaseNeededPure(true,58,59,30));
   Check("DCA priority no release without Pyramid",
         !Pyramid_DcaPriorityReleaseNeededPure(true,59,59,0));
   Check("DCA priority no release before DCA is actually due",
         !Pyramid_DcaPriorityReleaseNeededPure(false,59,59,30));

   Check("TP loss recovery shift", Near(Pyramid_TpRecoveryShiftPure(-50.0,0.10,1.0,0.01),5.0));
   Check("BUY economic TP shifted away", Near(Pyramid_AdjustTpLevelPure(0,4002.0,-50.0,0.10,1.0,0.01),4007.0));
   Check("SELL economic TP shifted away", Near(Pyramid_AdjustTpLevelPure(1,3998.0,-50.0,0.10,1.0,0.01),3993.0));
   Check("positive realized never pulls TP closer", Near(Pyramid_AdjustTpLevelPure(0,4002.0,25.0,0.10,1.0,0.01),4002.0));

   // T17.3 MoneyGuard: absolute money uses raw current floating, not campaign realized.
   Check("raw floating 350 hits 300 MoneyTP despite historical loss", MG_MoneyTpHit(350.0,300.0));
   Check("raw floating below target does not hit", !MG_MoneyTpHit(299.99,300.0));
   Check("legacy PctDiff tiny positive decision shape hits",
         MG_PctDiffHit(-2.21,2.47,10.0));
   Check("PctDiff execution buffer blocks tiny surplus",
         !MG_PctDiffHitBuffered(-2.21,2.47,10.0,1.0));
   Check("PctDiff execution buffer allows robust surplus",
         MG_PctDiffHitBuffered(-10.0,15.0,10.0,3.0));
   Check("guard latch starts",
         MG_LatchNextPure(GUARD_NONE,GUARD_CLOSE_ACCOUNT,false)==GUARD_CLOSE_ACCOUNT);
   Check("guard latch survives threshold retreat",
         MG_LatchNextPure(GUARD_CLOSE_ACCOUNT,GUARD_NONE,false)==GUARD_CLOSE_ACCOUNT);
   Check("guard latch clears only after flat",
         MG_LatchNextPure(GUARD_CLOSE_ACCOUNT,GUARD_NONE,true)==GUARD_NONE);

   int serial=3;
   int openPyramid=3;
   openPyramid--;
   serial=Pyramid_NextSerialLevelPure(serial);
   double anchor=Pyramid_T173RearmAnchorPure(4020.0,3990.0,90000,100000,120000,4030.0);
   Check("post Peel restores concurrent slot", Pyramid_ConcurrentAddAllowedPure(openPyramid,3));
   Check("post Peel uses next serial P4", serial==4);
   Check("post Peel no historical extreme anchor", Near(anchor,4030.0));
   Check("P4 requires fresh excursion from Peel exit", Pyramid_FavorableGapHitPure(0,anchor,4049.9,4050.0,20.0));

   serial=Pyramid_NextSerialLevelPure(serial);
   anchor=Pyramid_T173RearmAnchorPure(0.0,3990.0,140000,100000,120000,4030.0);
   Check("DCA epoch serial continues after Peel", serial==5);
   Check("DCA epoch falls back current BE", Near(anchor,3990.0));
   Check("DCA recovery can trigger Pyramid from current BE", Pyramid_FavorableGapHitPure(0,anchor,4009.9,4010.0,20.0));

   double brokerMin=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   if(brokerMin>0.0)
      Check("DCA-style normalization lifts sub-min fixed lot to broker minimum",
            Grid_NormalizeVolume(brokerMin*0.5)+1e-12>=brokerMin);
   else
      Check("broker minimum metadata available", false);

   PrintFormat("Pyramid T17.3 tests: %d passed, %d failed",g_pass,g_fail);
   if(g_fail==0) Print("ALL GREEN — T17.3 guard-priority + rearm + DCA coexistence + fixed-lot economics passed.");
}
