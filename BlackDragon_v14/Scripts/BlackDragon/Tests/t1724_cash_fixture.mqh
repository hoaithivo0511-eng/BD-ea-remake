// Broker-history fixture shared by native MQL and the host adapter. The
// production CashLedger class is included unchanged except C++ array syntax.
struct ST1724Deal
{
   ulong id,position;
   long owner,entry,type;
   datetime time;
   double profit,swap,commission,fee;
};
ST1724Deal t1724_db[32];
int t1724_count=0,t1724_selectedCount=0;
ulong t1724_selected[32];
bool t1724_historyOk=true;
void T1724ResetHistory()
{ t1724_count=0; t1724_selectedCount=0; t1724_historyOk=true; }
void T1724Add(const ulong id,const ulong position,const long owner,const long entry,
             const datetime time,const double profit,const double commission,const double fee)
{
   int i=t1724_count++;
   t1724_db[i].id=id; t1724_db[i].position=position; t1724_db[i].owner=owner;
   t1724_db[i].entry=entry; t1724_db[i].type=DEAL_TYPE_BUY;
   t1724_db[i].time=time; t1724_db[i].profit=profit; t1724_db[i].swap=0;
   t1724_db[i].commission=commission; t1724_db[i].fee=fee;
}
int T1724Find(const ulong id)
{ for(int i=0;i<t1724_count;i++) if(t1724_db[i].id==id) return i; return -1; }
bool T1724HistorySelect(const datetime from,const datetime to)
{
   t1724_selectedCount=0; if(!t1724_historyOk) return false;
   for(int i=0;i<t1724_count;i++)
      if(t1724_db[i].time>=from && t1724_db[i].time<=to)
         t1724_selected[t1724_selectedCount++]=t1724_db[i].id;
   return true;
}
bool T1724HistorySelectByPosition(const ulong id)
{
   t1724_selectedCount=0; if(!t1724_historyOk) return false;
   for(int i=0;i<t1724_count;i++)
      if(t1724_db[i].position==id) t1724_selected[t1724_selectedCount++]=t1724_db[i].id;
   return true;
}
bool T1724HistoryDealSelect(const ulong id)
{
   t1724_selectedCount=0;
   if(!t1724_historyOk || T1724Find(id)<0) return false;
   t1724_selected[0]=id; t1724_selectedCount=1; return true;
}
int T1724HistoryDealsTotal() { return t1724_selectedCount; }
ulong T1724HistoryDealGetTicket(const int index)
{ return index>=0 && index<t1724_selectedCount ? t1724_selected[index] : 0; }
string T1724HistoryDealGetString(const ulong id,const int property)
{ return T1724Find(id)>=0 ? "fixture" : ""; }
long T1724HistoryDealGetInteger(const ulong id,const int property)
{
   int i=T1724Find(id); if(i<0) return 0;
   if(property==DEAL_MAGIC) return t1724_db[i].owner;
   if(property==DEAL_ENTRY) return t1724_db[i].entry;
   if(property==DEAL_TYPE) return t1724_db[i].type;
   if(property==DEAL_POSITION_ID) return (long)t1724_db[i].position;
   if(property==DEAL_TIME_MSC) return (long)t1724_db[i].time*1000;
   return (long)t1724_db[i].time;
}
double T1724HistoryDealGetDouble(const ulong id,const int property)
{
   int i=T1724Find(id); if(i<0) return 0;
   if(property==DEAL_PROFIT) return t1724_db[i].profit;
   if(property==DEAL_SWAP) return t1724_db[i].swap;
   if(property==DEAL_COMMISSION) return t1724_db[i].commission;
   return t1724_db[i].fee;
}
#define HistorySelect T1724HistorySelect
#define HistorySelectByPosition T1724HistorySelectByPosition
#define HistoryDealSelect T1724HistoryDealSelect
#define HistoryDealsTotal T1724HistoryDealsTotal
#define HistoryDealGetTicket T1724HistoryDealGetTicket
#define HistoryDealGetString T1724HistoryDealGetString
#define HistoryDealGetInteger T1724HistoryDealGetInteger
#define HistoryDealGetDouble T1724HistoryDealGetDouble
#include <BlackDragon/CashLedger.mqh>
#undef HistorySelect
#undef HistorySelectByPosition
#undef HistoryDealSelect
#undef HistoryDealsTotal
#undef HistoryDealGetTicket
#undef HistoryDealGetString
#undef HistoryDealGetInteger
#undef HistoryDealGetDouble

void T1724RunCashCases()
{
   datetime day=100*86400,now=day+100;
   T1724ResetHistory();
   T1724Add(10,100,1000,DEAL_ENTRY_IN,day+1,0,-1,-0.2);
   T1724Add(20,100,0,DEAL_ENTRY_OUT,day+2,10,-1,-0.2); // manual close actor
   T1724Add(30,200,2000,DEAL_ENTRY_IN,day+3,0,-2,-0.1);
   T1724Add(40,200,2000,DEAL_ENTRY_OUT_BY,day+4,5,-2,-0.1);
   T1724Add(50,300,3000,DEAL_ENTRY_IN,day+5,100,0,0); // another EA
   CScopedDayCashLedger core,rh;
   core.Configure("fixture",1000,false); rh.Configure("fixture",2000,false);
   T1724Check("Q15 seed succeeds despite resetting selected history",core.Refresh(now));
   T1724Check("Q15 exact Core booked cash 7.6",MathAbs(core.Cash()-7.6)<1e-8);
   T1724Check("Q18 manual close actor retains original EA ownership",core.Contains(20));
   T1724Check("Q18 other EA excluded",!core.Contains(50));
   T1724Check("Q17 Recovery seed",rh.Refresh(now));
   T1724Check("Q17 Recovery entry fees and close-by included",MathAbs(rh.Cash()-0.8)<1e-8);
   T1724Check("Q15 duplicate observe succeeds",core.Observe(20,now));
   T1724Check("Q15 duplicate cash unchanged",MathAbs(core.Cash()-7.6)<1e-8);
   t1724_db[1].profit=12;
   T1724Check("Q14 cash correction replaces deal",core.Observe(20,now));
   T1724Check("Q14 correction delta exact",MathAbs(core.Cash()-9.6)<1e-8);
   core.Invalidate();
   T1724Check("Q14 correction reseed",core.Refresh(now));
   T1724Check("Q14 seed equals incremental corrected cash",MathAbs(core.Cash()-9.6)<1e-8);
   t1724_historyOk=false;
   core.Invalidate();
   T1724Check("Q19 unavailable history is invalid",!core.Refresh(now) && !core.Valid());
   t1724_historyOk=true;
   T1724Check("Q19 recovery without position mutation",core.Refresh(now+2));
   T1724Check("Q19 recovered ledger exact",MathAbs(core.Cash()-9.6)<1e-8);
   T1724Check("Q16 new day refresh",core.Refresh(day+86400+5));
   T1724Check("Q16 new day has no prior-day cash",MathAbs(core.Cash())<1e-8);
   T1724Check("Q16 delayed yesterday deal does not leak today",core.Observe(20,day+86400+5) && MathAbs(core.Cash())<1e-8);
   T1724Add(60,100,0,DEAL_ENTRY_OUT,day+86400+1,3,0,-0.1);
   T1724Check("Q16 overnight close exact booking-day cash",core.Observe(60,day+86400+5) && MathAbs(core.Cash()-2.9)<1e-8);
   T1724Add(70,400,0,DEAL_ENTRY_IN,day+86400+2,2,0,0);
   T1724Check("Q18 unowned manual excluded by default",core.Observe(70,day+86400+5) && MathAbs(core.Cash()-2.9)<1e-8);
   core.Configure("fixture",1000,true);
   T1724Check("Q18 manual scope opt-in",core.Refresh(day+86400+5) && MathAbs(core.Cash()-4.9)<1e-8);
   T1724Add(80,0,1000,DEAL_ENTRY_IN,day+86400+3,-9,0,0);
   t1724_db[7].type=99; // an account-level fee, not an attributable trade deal
   T1724Check("Q18 no guessed account fee attribution",core.Observe(80,day+86400+5) && MathAbs(core.Cash()-4.9)<1e-8);
   ulong reads=core.HistoryReads();
   T1724Check("Q31 quiet refresh",core.Refresh(day+86400+6));
   T1724Check("Q31 quiet refresh performs no history reads",core.HistoryReads()==reads);
   T1724Check("D203 retry sequence 1/2/4/8/16/30",PyProtect_RetryDelayPure(1)==1 &&
      PyProtect_RetryDelayPure(2)==2 && PyProtect_RetryDelayPure(3)==4 &&
      PyProtect_RetryDelayPure(4)==8 && PyProtect_RetryDelayPure(5)==16 && PyProtect_RetryDelayPure(8)==30);
   T1724Check("Q09 reject nonce mismatch refused",!PyProtect_ExactRejectIdentityPure(1,10,1,11));
   T1724Check("Q09 reject immutable ID mismatch refused",!PyProtect_ExactRejectIdentityPure(2,10,1,10));
   T1724Check("Q07 exact reject identity accepted",PyProtect_ExactRejectIdentityPure(1,10,1,10));
   CScopedDayCashLedger unavailable; unavailable.Configure("fixture",1000,false);
   t1724_historyOk=false;
   T1724Check("Q19 initial unavailable seed is invalid",!unavailable.Refresh(now));
   reads=unavailable.HistoryReads(); unavailable.Refresh(now); unavailable.Refresh(now);
   T1724Check("Q19 new-day failure does not poll on every tick",unavailable.HistoryReads()==reads);
   t1724_historyOk=true;
}
