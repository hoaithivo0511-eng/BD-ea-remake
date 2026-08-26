//+------------------------------------------------------------------+
//| RunT177JournalTests.mq5 — T17.7 C6 Vietnamese journal locks     |
//+------------------------------------------------------------------+
#property script_show_inputs
#include <BlackDragon/JournalT177.mqh>

int g_pass=0,g_fail=0;
void Check(const string name,const bool cond)
{
   if(cond){g_pass++;return;}
   g_fail++; Print("FAIL: ",name);
}
void OnStart()
{
   Check("prefix wait",Journal_T177StartsWithPure("CHỜ BUY | x","CHỜ "));
   Check("prefix negative",!Journal_T177StartsWithPure("CẢNH BÁO","CHỜ "));
   Check("translate max concurrent",StringFind(Journal_T177HumanReasonPure("BLOCK_MAX_CONCURRENT"),"giới hạn")>=0);
   Check("translate clean cycle",StringFind(Journal_T177HumanReasonPure("BLOCK_CLEAN_CYCLE_EXITED"),"Chu kỳ sạch")>=0);
   Check("translate max orders",StringFind(Journal_T177HumanReasonPure("BLOCK_MAX_ORDERS"),"tổng số lệnh")>=0);
   Check("translate dca reserve",StringFind(Journal_T177HumanReasonPure("BLOCK_DCA_RESERVE"),"DCA Core")>=0);
   Check("translate recovery",StringFind(Journal_T177HumanReasonPure("BLOCK_RECOVERY"),"Recovery cùng phía")>=0);
   Check("translate pending",StringFind(Journal_T177HumanReasonPure("BLOCK_PENDING"),"broker")>=0);
   Check("translate trend",StringFind(Journal_T177HumanReasonPure("BLOCK_TREND"),"Xu hướng")>=0);
   Check("translate timing",StringFind(Journal_T177HumanReasonPure("BLOCK_TIMING_MUTATION"),"MinuteStop")>=0);
   Check("translate economic",StringFind(Journal_T177HumanReasonPure("BLOCK_MIN_PROFIT_ECONOMIC"),"Lợi nhuận kinh tế")>=0);
   Check("translate tp room",StringFind(Journal_T177HumanReasonPure("BLOCK_TP_ROOM"),"TP")>=0);
   Check("translate first core",StringFind(Journal_T177HumanReasonPure("BLOCK_FIRST_CORE_IDENTITY"),"Core đầu")>=0);
   Check("translate gap",StringFind(Journal_T177HumanReasonPure("BLOCK_GAP"),"khoảng giá")>=0);
   Check("translate fixed reserve",StringFind(Journal_T177HumanReasonPure("BLOCK_FIXED_LOT_PEEL_RESERVE"),"tài trợ")>=0);
   Check("translate risk",StringFind(Journal_T177HumanReasonPure("BLOCK_RISK_BUDGET"),"ngân sách")>=0);
   Check("translate volume",StringFind(Journal_T177HumanReasonPure("BLOCK_VOLUME_GRID"),"broker")>=0);
   Check("translate capacity wait",StringFind(Journal_T177HumanReasonPure("CAPACITY_WAIT"),"sức chứa")>=0);
   Check("translate reconcile",StringFind(Journal_T177HumanReasonPure("RECONCILE_REQUIRED"),"đối soát")>=0);
   Check("translate hedge building",Journal_T177HumanReasonPure("HEDGE_BUILDING")=="Đang xây Hedge");
   Check("translate leg2 wait",StringFind(Journal_T177HumanReasonPure("LEG2_WAIT_SAFE"),"Lệnh 2")>=0);
   string line=Journal_T177LinePure("CHỜ","BUY","Hedge chưa tăng bậc","BLOCK_GAP","đang=81% mục tiêu=85% còn=4%");
   Check("line side state",StringFind(line,"CHỜ BUY | Hedge chưa tăng bậc")>=0);
   Check("line human reason",StringFind(line,"Chưa đủ khoảng giá")>=0);
   Check("line metric",StringFind(line,"đang=81% mục tiêu=85% còn=4%")>=0);
   Print("T17.7 C6 journal tests: ",g_pass," passed, ",g_fail," failed");
   if(g_fail==0) Print("ALL GREEN"); else Print("TESTS FAILED");
}
