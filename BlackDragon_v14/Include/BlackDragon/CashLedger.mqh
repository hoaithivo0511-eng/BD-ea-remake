#ifndef BD_CASH_LEDGER_MQH
#define BD_CASH_LEDGER_MQH
// T17.24: one booking-day cash reducer for Core and Recovery. This is a
// read-only broker-history consumer: it never sends orders or guesses fees.
struct SBDCashDeal
{
   ulong id;
   double cash;
};

double BD_DealCashPure(const double profit,const double swap,
                       const double commission,const double fee)
{ return profit+swap+commission+fee; }

bool BD_CashEntryPure(const long entry)
{ return entry==DEAL_ENTRY_IN || entry==DEAL_ENTRY_OUT ||
         entry==DEAL_ENTRY_INOUT || entry==DEAL_ENTRY_OUT_BY; }

class CScopedDayCashLedger
{
private:
   string m_symbol;
   long m_magic;
   bool m_manual;
   bool m_valid;
   bool m_dirty;
   datetime m_day;
   datetime m_retryAt;
   double m_cash;
   SBDCashDeal m_deals[]; // sorted exact deal IDs; no timestamp-only dedup
   ulong m_ownerIds[];
   long m_ownerMagic[];
   ulong m_historyReads;

   datetime Day(const datetime now) const
   { return StringToTime(TimeToString(now,TIME_DATE)); }
   int LowerDeal(const ulong id) const
   {
      int lo=0,hi=ArraySize(m_deals);
      while(lo<hi) { int mid=lo+(hi-lo)/2;
         if(m_deals[mid].id<id) lo=mid+1; else hi=mid; }
      return lo;
   }
   int LowerOwner(const ulong id) const
   {
      int lo=0,hi=ArraySize(m_ownerIds);
      while(lo<hi) { int mid=lo+(hi-lo)/2;
         if(m_ownerIds[mid]<id) lo=mid+1; else hi=mid; }
      return lo;
   }
   bool ResolveOwner(const ulong id,long &owner)
   {
      if(id==0) return false;
      int at=LowerOwner(id),n=ArraySize(m_ownerIds);
      if(at<n && m_ownerIds[at]==id) { owner=m_ownerMagic[at]; return true; }
      m_historyReads++;
      if(!HistorySelectByPosition(id)) return false;
      ulong first=0; long firstMsc=0;
      for(int i=0;i<HistoryDealsTotal();i++)
      {
         ulong deal=HistoryDealGetTicket(i);
         if(deal==0) return false;
         if(HistoryDealGetString(deal,DEAL_SYMBOL)!=m_symbol ||
            (ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID)!=id) continue;
         long entry=HistoryDealGetInteger(deal,DEAL_ENTRY);
         if(entry!=DEAL_ENTRY_IN && entry!=DEAL_ENTRY_INOUT) continue;
         long stamp=HistoryDealGetInteger(deal,DEAL_TIME_MSC);
         if(first==0 || stamp<firstMsc || (stamp==firstMsc && deal<first))
         { first=deal; firstMsc=stamp; owner=HistoryDealGetInteger(deal,DEAL_MAGIC); }
      }
      if(first==0) return false;
      if(ArrayResize(m_ownerIds,n+1,128)!=n+1 ||
         ArrayResize(m_ownerMagic,n+1,128)!=n+1)
      { ArrayResize(m_ownerIds,n); ArrayResize(m_ownerMagic,n); return false; }
      for(int j=n;j>at;j--)
      { m_ownerIds[j]=m_ownerIds[j-1]; m_ownerMagic[j]=m_ownerMagic[j-1]; }
      m_ownerIds[at]=id; m_ownerMagic[at]=owner;
      return true;
   }
   bool Read(const ulong deal,const datetime day,bool &included,double &cash)
   {
      included=false; cash=0;
      if(deal==0 || !HistoryDealSelect(deal)) return false;
      if(HistoryDealGetString(deal,DEAL_SYMBOL)!=m_symbol) return true;
      long type=HistoryDealGetInteger(deal,DEAL_TYPE);
      if(type!=DEAL_TYPE_BUY && type!=DEAL_TYPE_SELL) return true;
      datetime stamp=(datetime)HistoryDealGetInteger(deal,DEAL_TIME);
      if(stamp<day || stamp>=day+86400) return true;
      if(!BD_CashEntryPure(HistoryDealGetInteger(deal,DEAL_ENTRY))) return true;
      ulong id=(ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID);
      // Capture the deal before ownership lookup changes selected history.
      cash=BD_DealCashPure(HistoryDealGetDouble(deal,DEAL_PROFIT),
                         HistoryDealGetDouble(deal,DEAL_SWAP),
                         HistoryDealGetDouble(deal,DEAL_COMMISSION),
                         HistoryDealGetDouble(deal,DEAL_FEE));
      if(!MathIsValidNumber(cash)) return false;
      long owner=0;
      if(!ResolveOwner(id,owner)) return false;
      included=owner==m_magic || (owner==0 && m_manual);
      return true;
   }
   bool Put(const ulong id,const double cash)
   {
      int at=LowerDeal(id),n=ArraySize(m_deals);
      if(at<n && m_deals[at].id==id)
      { m_cash+=cash-m_deals[at].cash; m_deals[at].cash=cash; return true; }
      if(ArrayResize(m_deals,n+1,256)!=n+1) return false;
      for(int i=n;i>at;i--) m_deals[i]=m_deals[i-1];
      m_deals[at].id=id; m_deals[at].cash=cash; m_cash+=cash;
      return true;
   }
public:
   CScopedDayCashLedger() : m_symbol(""),m_magic(0),m_manual(false),
      m_valid(false),m_dirty(true),m_day(0),m_retryAt(0),m_cash(0),m_historyReads(0) {}
   void Configure(const string symbol,const long magic,const bool manual)
   {
      if(m_symbol==symbol && m_magic==magic && m_manual==manual) return;
      m_symbol=symbol; m_magic=magic; m_manual=manual; m_dirty=true; m_valid=false;
      m_day=0; m_retryAt=0; ArrayResize(m_ownerIds,0); ArrayResize(m_ownerMagic,0);
   }
   void Invalidate()
   {
      m_dirty=true; m_valid=false; m_retryAt=0;
      // A correction may change ownership as well as cash/date.
      ArrayResize(m_ownerIds,0); ArrayResize(m_ownerMagic,0);
   }
   bool Valid() const { return m_valid && !m_dirty; }
   double Cash() const { return m_cash; } // consumer MUST check Valid()
   datetime DayStart() const { return m_day; }
   ulong HistoryReads() const { return m_historyReads; }
   bool Contains(const ulong id) const
   { int at=LowerDeal(id); return at<ArraySize(m_deals) && m_deals[at].id==id; }
   bool Seed(const datetime now)
   {
      datetime day=Day(now);
      // Anchor the attempted day even on history failure, otherwise Refresh
      // would reset the retry deadline on every tick of the new day.
      m_day=day;
      m_valid=false; m_dirty=true; m_retryAt=now+1; m_historyReads++;
      if(!HistorySelect(day,now+1)) return false;
      // Freeze every ID BEFORE Read/ResolveOwner resets the terminal's list.
      int n=HistoryDealsTotal(); ulong ids[];
      if(ArrayResize(ids,n)!=n) return false;
      for(int i=0;i<n;i++) { ids[i]=HistoryDealGetTicket(i); if(ids[i]==0) return false; }
      ArrayResize(m_deals,0); m_cash=0; m_day=day;
      for(int i=0;i<n;i++)
      {
         bool included; double cash;
         if(!Read(ids[i],day,included,cash)) return false;
         if(included && !Put(ids[i],cash)) return false;
      }
      m_valid=true; m_dirty=false; m_retryAt=0;
      return true;
   }
   bool Refresh(const datetime now)
   {
      if(now<m_day || now>=m_day+86400) { m_dirty=true; m_valid=false; m_retryAt=0;
         ArrayResize(m_ownerIds,0); ArrayResize(m_ownerMagic,0); }
      if(Valid()) return true;
      if(now<m_retryAt) return false;
      return Seed(now);
   }
   bool Observe(const ulong deal,const datetime now)
   {
      if(!Refresh(now)) return false;
      bool included; double cash;
      if(!Read(deal,m_day,included,cash))
      { m_dirty=true; m_valid=false; m_retryAt=now+1; return false; }
      // A duplicate with changed cash is replaced, not added twice. A deal
      // moved outside today's scope contributes zero if it was already booked.
      if(included || Contains(deal))
         if(!Put(deal,included ? cash : 0))
         { m_dirty=true; m_valid=false; return false; }
      return true;
   }
};
#endif
