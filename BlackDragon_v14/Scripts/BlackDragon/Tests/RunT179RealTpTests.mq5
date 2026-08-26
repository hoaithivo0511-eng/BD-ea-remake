//+------------------------------------------------------------------+
//| RunT179RealTpTests.mq5 — native T17.9 policy + interleave       |
//+------------------------------------------------------------------+
#property script_show_inputs
#include <BlackDragon/Recovery/RecoveryT179RealTpPolicy.mqh>

int g_pass=0,g_fail=0;
void Check(const string name,const bool ok)
{
   if(ok){g_pass++;return;}
   g_fail++; Print("FAIL: ",name);
}

bool Contains(const ulong &ids[],const ulong wanted)
{
   for(int i=0;i<ArraySize(ids);i++) if(ids[i]==wanted) return true;
   return false;
}

void OnStart()
{
   Check("strict expected",Recovery_T179StrictBrokerTpProofPure(true,true,true,true,4079.896,4079.891,0.02));
   Check("strict virtual rejected",!Recovery_T179StrictBrokerTpProofPure(false,true,true,true,4079.896,4079.896,0.02));
   Check("strict config rejected",!Recovery_T179StrictBrokerTpProofPure(true,false,true,true,4079.896,4079.896,0.02));
   Check("strict owner rejected",!Recovery_T179StrictBrokerTpProofPure(true,true,false,true,4079.896,4079.896,0.02));
   Check("strict reason rejected",!Recovery_T179StrictBrokerTpProofPure(true,true,true,false,4079.896,4079.896,0.02));
   Check("strict fill rejected",!Recovery_T179StrictBrokerTpProofPure(true,true,true,true,4079.896,4080.5,0.02));
   Check("preownership ignores live cohort",Recovery_T179ClassifyBrokerTpPure(true,false,false,false,false)==RECOVERY_T179_TP_PREOWNERSHIP);
   Check("owned epoch accepted",Recovery_T179ClassifyBrokerTpPure(true,true,true,true,true)==RECOVERY_T179_TP_DURABLE_EPOCH);
   Check("owned missing epoch rejected",Recovery_T179ClassifyBrokerTpPure(true,true,false,true,true)==RECOVERY_T179_TP_EXTERNAL);
   Check("owned wrong target rejected",Recovery_T179ClassifyBrokerTpPure(true,true,true,false,true)==RECOVERY_T179_TP_EXTERNAL);
   Check("owned new id rejected",Recovery_T179ClassifyBrokerTpPure(true,true,true,true,false)==RECOVERY_T179_TP_EXTERNAL);
   Check("price starts",Recovery_T179SettlementStartsPure(true,false,true,false));
   Check("callback starts",Recovery_T179SettlementStartsPure(true,false,false,true));
   Check("settling blocks",Recovery_T179BlocksSameSideAddPure(false,true));
   Check("fault blocks",Recovery_T179BlocksSameSideAddPure(true,false));
   Check("idle allows",!Recovery_T179BlocksSameSideAddPure(false,false));
   Check("complete flat",Recovery_T179SettlementCompletePure(true,true,0,0,false));
   Check("core delays",!Recovery_T179SettlementCompletePure(true,true,1,0,false));
   Check("hedge delays",!Recovery_T179SettlementCompletePure(true,true,0,1,false));
   Check("reconcile delays",!Recovery_T179SettlementCompletePure(true,true,0,0,true));
   Check("modify exact",Recovery_T179ModifyCandidatePure(10,true,10,true,true,true,0.1));
   Check("modify vanished",!Recovery_T179ModifyCandidatePure(10,false,0,true,true,true,0.1));
   Check("modify drift",!Recovery_T179ModifyCandidatePure(10,true,14,true,true,true,0.1));
   Check("modify flat",!Recovery_T179ModifyCandidatePure(10,true,10,true,true,true,0.0));

   ulong epoch[4]={10,11,12,13};
   bool settling=Recovery_T179SettlementStartsPure(true,false,true,false);
   int adds=0,expected=0,external=0;
   if(!Recovery_T179BlocksSameSideAddPure(false,settling)) adds++;
   for(int i=0;i<4;i++)
   {
      eRecoveryT179RealTpProof p=Recovery_T179ClassifyBrokerTpPure(true,true,true,true,Contains(epoch,epoch[i]));
      if(p==RECOVERY_T179_TP_DURABLE_EPOCH) expected++; else external++;
      if(!Recovery_T179BlocksSameSideAddPure(false,settling)) adds++;
   }
   Check("fixture barrier armed",settling);
   Check("fixture no interleaved add",adds==0);
   Check("fixture four expected",expected==4);
   Check("fixture no external latch",external==0);
   Check("fixture new id excluded",!Contains(epoch,14));
   Check("fixture no stale modify",!Recovery_T179ModifyCandidatePure(10,false,0,true,true,true,0.1));
   Check("fixture no reconcile",Recovery_T179SettlementCompletePure(true,true,0,0,false));
   settling=false;
   Check("fixture next campaign",!Recovery_T179BlocksSameSideAddPure(false,settling));

   Print("T17.9 REAL-TP tests: ",g_pass," passed, ",g_fail," failed");
   if(g_fail==0) Print("ALL GREEN"); else Print("TESTS FAILED");
}
