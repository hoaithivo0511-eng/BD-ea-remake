#ifndef BD_PYRAMID_PROTECTION_MQH
#define BD_PYRAMID_PROTECTION_MQH
// digits-tested: 3, 5

#include "PyramidProtectionPolicy.mqh"
#include <BlackDragon/BasketManager.mqh>
#include <BlackDragon/Recovery/RecoveryEngine.mqh>

enum ePyProtectPhase { PY_EMPTY=0,PY_WATCH,PY_PREPARE,PY_ARMED,PY_CLOSING };
struct SPyProtectGroup
{
   int phase;
   int mode;
   long serial;
   double stop;
   double candidate;
   double peak;
   double floorCash;
   double trimCash;
   ulong coreStartDeal;
   long coreStartMsc;
   double campaignTrimCash;
   ulong releaseTicket; // durable Core-PY peel/standalone-exit coordination
   long releaseUnits;
};
struct SPyProtectMember
{
   int dir;
   int mode;
   long serial;
   ulong id;
   ulong ticket;
   double cash;       // All booked cash on this exact position, entry costs included once.
   double entryCost;
   double entryLots;
   double confirmedSl;
   double requestedSl;
};
struct SPyProtectOperation
{
   int dir;
   int kind;
   ulong coreStartDeal;
   long serial;
   ulong ticket;
   ulong id;
   long nonce;
   double beforeLots;
   double requestedLots;
   double targetSl;
   bool complete;
};
struct SPyProtectSnapshot
{
   int count;
   double lots;
   double weighted;
   double floating;
   double swap;
   double exitFees;
   double booked;
   bool valid;
};
struct SPyProtectBinding { int sideIndex; int memberIndex; };
struct SPyProtectRequestView
{
   bool opening;
   bool pyramid;
   int dir;
   long owner;
   double closingLots;
};
enum ePyProtectDriveResult
{
   PY_DRIVE_NEXT=-1,
   PY_DRIVE_ALLOW=0,
   PY_DRIVE_BLOCK=1,
   PY_DRIVE_WAIT_UNFUNDED=2
};
struct SPyProtectDisk
{
   uint signature;
   uint version;
   uint checksum;
   long account;
   long coreMagic;
   long hedgeMagic;
   uint symbol;
   uint semantics;
   int members;
   int operations;
   long nonce;
};

// Extends existing basket/executor/ARCS primitives. This adapter has no steady
// tick whole-account scan and no tick-driven campaign history query.
class CPyramidProtection : public IPyramidProtection
{
private:
   CBasketManager *m_basket;
   CExecutionLayer *m_exec;
   CRecoveryEngine *m_recovery;
   SPyProtectGroup m_group[2];
   SPyProtectSnapshot m_snap[2];
   SPyProtectMember m_members[];
   SPyProtectOperation m_ops[];
   SPyProtectBinding m_buy[];
   SPyProtectBinding m_sell[];
   ulong m_basketRevision;
   bool m_historyDirty;
   bool m_fault;
   bool m_recovered;
   bool m_override;
   long m_nonce;
   string m_file;
   double m_tick;
   double m_step;
   double m_pip;
   double m_point;
   double m_slope;
   double m_booked[2];
   EAContext m_context;
   ulong m_observeCalls;
   ulong m_rebinds;
   ulong m_historyRefreshes;
   ulong m_exposureScans;
   ulong m_trimScans;
   ulong m_scanVisits;

   int Key(const int d) const { return 172200+d; }
   eRecoveryCoreDirection Rdir(const int d) const
   { return d==0 ? recovery_CORE_BUY : recovery_CORE_SELL; }
   bool Enabled() const { return PyramidSLMode_!=py_protect_OFF; }
   bool Persisted() const
   { return !MQLInfoInteger(MQL_TESTER) || RecoveryTesterResumeState_; }
   uint Semantics() const
   {
      return Recovery_StringHash((string)(int)PyramidSLMode_+"|"+
         DoubleToString(PyramidBETriggerPips_,12)+"|"+DoubleToString(PyramidLockProfitPips_,12)+"|"+
         DoubleToString(PyramidLockSafetyPips_,12)+"|"+DoubleToString(PyramidTrailGapPips_,12));
   }
   void Fault(const string why)
   {
      if(!m_fault) Log_Error("PYProtect","T17.22 đối soát: "+why);
      m_fault=true;
   }
   uint HashBytes(const uchar &bytes[]) const
   {
      uint h=2166136261;
      for(int i=0;i<ArraySize(bytes);i++) { h^=(uint)bytes[i]; h*=16777619; }
      return h;
   }
   bool Save()
   {
      if(!Persisted()) return true;
      if(m_group[0].phase==PY_EMPTY && m_group[1].phase==PY_EMPTY &&
         m_group[0].campaignTrimCash==0 && m_group[1].campaignTrimCash==0 && Pending()<0)
      { if(FileIsExist(m_file)) FileDelete(m_file); return true; }
      SPyProtectDisk h;
      ZeroMemory(h);
      h.signature=17220017; h.version=1;
      h.account=AccountInfoInteger(ACCOUNT_LOGIN); h.coreMagic=(long)Magic;
      h.hedgeMagic=(long)RecoveryMagic_; h.symbol=Recovery_StringHash(_Symbol);
      h.semantics=Semantics(); h.members=ArraySize(m_members); h.operations=ArraySize(m_ops); h.nonce=m_nonce;
      string tmp=m_file+".tmp";
      int f=FileOpen(tmp,FILE_BIN|FILE_WRITE);
      if(f==INVALID_HANDLE) { Fault("không ghi được state"); return false; }
      bool ok=FileWriteStruct(f,h)==sizeof(SPyProtectDisk);
      for(int d=0;d<2;d++) ok=FileWriteStruct(f,m_group[d])==sizeof(SPyProtectGroup) && ok;
      for(int i=0;i<h.members;i++) ok=FileWriteStruct(f,m_members[i])==sizeof(SPyProtectMember) && ok;
      for(int i=0;i<h.operations;i++) ok=FileWriteStruct(f,m_ops[i])==sizeof(SPyProtectOperation) && ok;
      FileFlush(f); FileClose(f);
      if(!ok) { Fault("ghi state thiếu byte"); return false; }
      f=FileOpen(tmp,FILE_BIN|FILE_READ|FILE_WRITE);
      if(f==INVALID_HANDLE) { Fault("không kiểm được state"); return false; }
      long size=(long)FileSize(f)-(long)sizeof(SPyProtectDisk);
      uchar bytes[]; ArrayResize(bytes,(int)size);
      ok=size>=0 && FileSeek(f,(long)sizeof(SPyProtectDisk),SEEK_SET) &&
         FileReadArray(f,bytes,0,(int)size)==(uint)size;
      h.checksum=HashBytes(bytes);
      ok=FileSeek(f,0,SEEK_SET) && FileWriteStruct(f,h)==sizeof(SPyProtectDisk) && ok;
      FileFlush(f); FileClose(f);
      if(!ok || !FileMove(tmp,0,m_file,FILE_REWRITE))
      { Fault("atomic state replace thất bại"); return false; }
      return true;
   }
   bool HeaderMatches(const SPyProtectDisk &h) const
   {
      return h.signature==17220017 && h.version==1 &&
             h.account==AccountInfoInteger(ACCOUNT_LOGIN) && h.coreMagic==(long)Magic &&
             h.hedgeMagic==(long)RecoveryMagic_ && h.symbol==Recovery_StringHash(_Symbol) &&
             h.semantics==Semantics() && h.members>=0 && h.members<=65536 &&
             h.operations>=0 && h.operations<=65536;
   }
   long PayloadSize(const SPyProtectDisk &h) const
   {
      return 2*(long)sizeof(SPyProtectGroup)+(long)h.members*sizeof(SPyProtectMember)+
             (long)h.operations*sizeof(SPyProtectOperation);
   }
   bool ReadPayload(const int f,const SPyProtectDisk &h,const long expected)
   {
      FileSeek(f,(long)sizeof(SPyProtectDisk),SEEK_SET);
      bool ok=true;
      for(int d=0;d<2;d++) ok=FileReadStruct(f,m_group[d])==sizeof(SPyProtectGroup) && ok;
      ArrayResize(m_members,h.members); ArrayResize(m_ops,h.operations);
      for(int i=0;i<h.members;i++) ok=FileReadStruct(f,m_members[i])==sizeof(SPyProtectMember) && ok;
      for(int i=0;i<h.operations;i++) ok=FileReadStruct(f,m_ops[i])==sizeof(SPyProtectOperation) && ok;
      return ok && (long)FileTell(f)==(long)sizeof(SPyProtectDisk)+expected;
   }
   bool LoadedStateValid(const SPyProtectDisk &h) const
   {
      for(int d=0;d<2;d++)
         if(m_group[d].phase<PY_EMPTY || m_group[d].phase>PY_CLOSING ||
            !MathIsValidNumber(m_group[d].stop) || !MathIsValidNumber(m_group[d].floorCash)) return false;
      for(int i=0;i<h.members;i++)
         if(m_members[i].dir<0 || m_members[i].dir>1 || m_members[i].id==0) return false;
      return true;
   }
   bool Load()
   {
      if(!Persisted() || !FileIsExist(m_file)) return true;
      int f=FileOpen(m_file,FILE_BIN|FILE_READ);
      if(f==INVALID_HANDLE) return false;
      SPyProtectDisk h;
      if(FileReadStruct(f,h)!=sizeof(SPyProtectDisk) || !HeaderMatches(h))
      { FileClose(f); return false; }
      long expected=PayloadSize(h);
      if((long)FileSize(f)!=(long)sizeof(SPyProtectDisk)+expected)
      { FileClose(f); return false; }
      uchar bytes[]; ArrayResize(bytes,(int)expected);
      if(FileReadArray(f,bytes,0,(int)expected)!=(uint)expected || HashBytes(bytes)!=h.checksum)
      { FileClose(f); return false; }
      bool ok=ReadPayload(f,h,expected);
      FileClose(f); m_nonce=h.nonce;
      return ok && LoadedStateValid(h);
   }
   int Find(const ulong id) const
   {
      for(int i=0;i<ArraySize(m_members);i++) if(m_members[i].id==id) return i;
      return -1;
   }
   int Pending() const
   {
      for(int i=ArraySize(m_ops)-1;i>=0;i--) if(!m_ops[i].complete) return i;
      return -1;
   }
   string Tag(const SPyProtectOperation &op) const
   { return (op.kind==EXEC_CMD_PY_RH_TRIM ? "PYR|HX|" : "PYR|PX|")+(string)op.nonce; }
   bool MatchesOperation(const ulong deal,const SPyProtectOperation &op)
   {
      if(!HistoryDealSelect(deal) || HistoryDealGetString(deal,DEAL_SYMBOL)!=_Symbol ||
         (ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID)!=op.id ||
         HistoryDealGetInteger(deal,DEAL_REASON)!=DEAL_REASON_EXPERT) return false;
      long entry=HistoryDealGetInteger(deal,DEAL_ENTRY);
      if(entry!=DEAL_ENTRY_OUT && entry!=DEAL_ENTRY_OUT_BY) return false;
      ulong order=(ulong)HistoryDealGetInteger(deal,DEAL_ORDER);
      if(order==0 || !HistoryOrderSelect(order)) return false;
      return HistoryOrderGetString(order,ORDER_COMMENT)==Tag(op);
   }
   bool OperationEffect(const int index,double &lots,double &cash)
   {
      lots=0; cash=0;
      SPyProtectOperation op=m_ops[index];
      if(!HistorySelectByPosition(op.id)) return false;
      ulong ids[]; int n=HistoryDealsTotal(); ArrayResize(ids,n);
      for(int i=0;i<n;i++) ids[i]=HistoryDealGetTicket(i);
      for(int i=0;i<n;i++)
      {
         if(ids[i]==0) return false;
         if(!MatchesOperation(ids[i],op)) continue;
         if(!HistoryDealSelect(ids[i])) return false;
         lots+=HistoryDealGetDouble(ids[i],DEAL_VOLUME);
         cash+=HistoryDealGetDouble(ids[i],DEAL_PROFIT)+HistoryDealGetDouble(ids[i],DEAL_SWAP)+
               HistoryDealGetDouble(ids[i],DEAL_COMMISSION)+HistoryDealGetDouble(ids[i],DEAL_FEE);
      }
      return true;
   }
   bool RefreshHistory()
   {
      m_historyRefreshes++;
      m_booked[0]=0; m_booked[1]=0;
      for(int i=0;i<ArraySize(m_members);i++)
      {
         int d=m_members[i].dir;
         if(m_group[d].phase==PY_EMPTY || m_members[i].serial!=m_group[d].serial) continue;
         if(!HistorySelectByPosition(m_members[i].id)) return false;
         double cash=0,fees=0,entries=0;
         bool owned=false;
         for(int j=0;j<HistoryDealsTotal();j++)
         {
            ulong deal=HistoryDealGetTicket(j);
            if(deal==0 || HistoryDealGetString(deal,DEAL_SYMBOL)!=_Symbol) return false;
            cash+=HistoryDealGetDouble(deal,DEAL_PROFIT)+HistoryDealGetDouble(deal,DEAL_SWAP)+
                  HistoryDealGetDouble(deal,DEAL_COMMISSION)+HistoryDealGetDouble(deal,DEAL_FEE);
            if(HistoryDealGetInteger(deal,DEAL_ENTRY)==DEAL_ENTRY_IN)
            {
               if(HistoryDealGetInteger(deal,DEAL_MAGIC)!=(long)Magic ||
                  !OC_IsPyramid(HistoryDealGetString(deal,DEAL_COMMENT))) return false;
               owned=true;
               entries+=HistoryDealGetDouble(deal,DEAL_VOLUME);
               fees+=HistoryDealGetDouble(deal,DEAL_COMMISSION)+HistoryDealGetDouble(deal,DEAL_FEE);
            }
         }
         if(!owned || entries<=0 || !MathIsValidNumber(cash)) return false;
         m_members[i].cash=cash; m_members[i].entryCost=fees; m_members[i].entryLots=entries;
         m_booked[d]+=cash;
      }
      for(int d=0;d<2;d++) { m_group[d].trimCash=0; m_group[d].campaignTrimCash=0; }
      for(int i=0;i<ArraySize(m_ops);i++)
         if(m_ops[i].kind==EXEC_CMD_PY_RH_TRIM &&
            m_ops[i].coreStartDeal==m_group[m_ops[i].dir].coreStartDeal && m_ops[i].coreStartDeal!=0)
         {
            double lots,cash;
            if(!OperationEffect(i,lots,cash)) return false;
            int d=m_ops[i].dir;
            m_group[d].campaignTrimCash+=cash;
            if(m_ops[i].serial==m_group[d].serial && m_group[d].phase!=PY_EMPTY) m_group[d].trimCash+=cash;
         }
      m_historyDirty=false;
      return true;
   }
   bool BindSide(const BasketSide &side,const int dir,SPyProtectBinding &binding[])
   {
      ArrayResize(binding,0);
      if(side.count==0)
      { m_group[dir].coreStartDeal=0; m_group[dir].coreStartMsc=0; m_group[dir].campaignTrimCash=0; }
      else if(m_group[dir].coreStartDeal==0)
      {
         datetime start=0;
         if(!Pyramid_FindActiveCampaignStart(side,dir,TimeCurrent(),start,
                                             m_group[dir].coreStartMsc,m_group[dir].coreStartDeal)) return false;
         m_historyDirty=true;
      }
      for(int i=0;i<side.count;i++)
      {
         if(!side.pos[i].isPyramid) continue;
         if(m_group[dir].phase==PY_EMPTY)
         { m_group[dir].phase=PY_WATCH; m_group[dir].mode=(int)PyramidSLMode_; m_group[dir].serial++; }
         int member=Find(side.pos[i].positionId);
         if(member<0)
         {
            if(m_group[dir].phase==PY_CLOSING) { Fault("PY mới xuất hiện trong cohort đang đóng"); return false; }
            member=ArraySize(m_members); ArrayResize(m_members,member+1);
            ZeroMemory(m_members[member]);
            m_members[member].dir=dir; m_members[member].mode=(int)PyramidSLMode_;
            m_members[member].serial=m_group[dir].serial; m_members[member].id=side.pos[i].positionId;
            m_historyDirty=true;
         }
         m_members[member].ticket=side.pos[i].ticket;
         int n=ArraySize(binding); ArrayResize(binding,n+1);
         binding[n].sideIndex=i; binding[n].memberIndex=member;
      }
      return true;
   }
   void Snapshot(const BasketSide &side,const int dir,const SPyProtectBinding &binding[])
   {
      SPyProtectSnapshot s; ZeroMemory(s); s.valid=true;
      s.booked=m_booked[dir];
      for(int i=0;i<ArraySize(binding);i++)
      {
         int k=binding[i].sideIndex,mi=binding[i].memberIndex;
         if(k>=side.count || side.pos[k].positionId!=m_members[mi].id) { s.valid=false; break; }
         PositionInfo p=side.pos[k];
         s.count++; s.lots+=p.lots; s.weighted+=p.openPrice*p.lots;
         s.floating+=p.profit; s.swap+=p.swap;
         if(m_members[mi].entryLots>0)
            s.exitFees+=MathMax(0.0,-m_members[mi].entryCost)*p.lots/m_members[mi].entryLots;
      }
      if(s.lots>0) s.weighted/=s.lots;
      m_snap[dir]=s;
   }
   double Reserve(const int d,const double lots) const
   {
      double proportion=m_snap[d].lots>0 ? lots/m_snap[d].lots : 0;
      return m_snap[d].exitFees*proportion+
             lots*m_slope*(PyramidLockSafetyPips_*m_pip+Cfg.SlippagePrice);
   }
   double NetAt(const int d,const double price) const
   {
      return PyProtect_NetAtPricePure(d,m_snap[d].weighted,m_snap[d].lots,price,m_slope,
         m_snap[d].booked,m_snap[d].swap,Reserve(d,m_snap[d].lots));
   }
   // Called at an actual mutation/arming boundary, never at each quiet tick.
   bool Exposure(const int d,long &core,long &hedge,long &reserved)
   {
      core=0; hedge=0; reserved=0;
      m_exposureScans++;
      m_scanVisits+=(ulong)PositionsTotal();
      for(int i=PositionsTotal()-1;i>=0;i--)
      {
         ulong ticket=PositionGetTicket(i);
         if(ticket==0) return false;
         if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
         long owner=PositionGetInteger(POSITION_MAGIC),type=PositionGetInteger(POSITION_TYPE);
         long units=Recovery_VolumeToUnitsFloor(PositionGetDouble(POSITION_VOLUME),m_step);
         if(owner==(long)Magic && type==(d==0 ? POSITION_TYPE_BUY : POSITION_TYPE_SELL))
         {
            core+=units;
            if(OC_IsPyramid(PositionGetString(POSITION_COMMENT))) reserved+=units;
         }
         if(owner==(long)RecoveryMagic_ && type==(d==0 ? POSITION_TYPE_SELL : POSITION_TYPE_BUY)) hedge+=units;
      }
      return true;
   }
   double CapPct() const { return Recovery_T177EffectiveHedgeAbsoluteMaxCoveragePercent(); }
   bool SelectTrim(const int d,const long excess,ulong &ticket,double &volume,double &net)
   {
      ticket=0; volume=0; net=0;
      // Latest generation/child first, so earlier retained layers stay intact.
      long newest=0;
      m_trimScans++;
      m_scanVisits+=(ulong)PositionsTotal();
      for(int i=PositionsTotal()-1;i>=0;i--)
      {
         ulong t=PositionGetTicket(i);
         if(t==0) return false;
         if(PositionGetString(POSITION_SYMBOL)!=_Symbol ||
            PositionGetInteger(POSITION_MAGIC)!=(long)RecoveryMagic_ ||
            PositionGetInteger(POSITION_TYPE)!=(d==0 ? POSITION_TYPE_SELL : POSITION_TYPE_BUY)) continue;
         long opened=PositionGetInteger(POSITION_TIME_MSC);
         if(ticket==0 || opened>newest || (opened==newest && t>ticket)) { ticket=t; newest=opened; }
      }
      if(ticket==0 || !PositionSelectByTicket(ticket)) return false;
      double live=PositionGetDouble(POSITION_VOLUME);
      long minUnits=Recovery_VolumeToUnitsFloor(SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN),m_step);
      long request=Recovery_ExitTrimRequestUnits(excess,Recovery_VolumeToUnitsFloor(live,m_step),minUnits);
      volume=Recovery_UnitsToVolume(request,m_step);
      if(live-volume>1e-9 && live-volume<SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN)-1e-9) volume=live;
      net=(PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP))*volume/live;
      ulong id=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
      if(!HistorySelectByPosition(id)) return false;
      double entryFees=0,entryLots=0;
      for(int i=0;i<HistoryDealsTotal();i++)
      {
         ulong deal=HistoryDealGetTicket(i); if(deal==0) return false;
         if(HistoryDealGetInteger(deal,DEAL_ENTRY)==DEAL_ENTRY_IN)
         { entryLots+=HistoryDealGetDouble(deal,DEAL_VOLUME);
           entryFees+=HistoryDealGetDouble(deal,DEAL_COMMISSION)+HistoryDealGetDouble(deal,DEAL_FEE); }
      }
      if(entryLots<=0) return false;
      net-=MathMax(0.0,-entryFees)*volume/entryLots+volume*m_slope*Cfg.SlippagePrice;
      return volume>0;
   }
   bool StartOperation(const int d,const int kind,const ulong ticket,const double volume,const double stop)
   {
      if(Pending()>=0 || !PositionSelectByTicket(ticket)) return false;
      int i=ArraySize(m_ops); ArrayResize(m_ops,i+1); ZeroMemory(m_ops[i]);
      m_ops[i].coreStartDeal=m_group[d].coreStartDeal;
      m_ops[i].dir=d; m_ops[i].serial=m_group[d].serial; m_ops[i].kind=kind; m_ops[i].ticket=ticket;
      m_ops[i].id=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
      m_ops[i].beforeLots=PositionGetDouble(POSITION_VOLUME); m_ops[i].requestedLots=volume;
      m_ops[i].targetSl=stop;
      long clock=(long)TimeCurrent()*100000; m_nonce=m_nonce+1>clock ? m_nonce+1 : clock; m_ops[i].nonce=m_nonce;
      if(kind==EXEC_CMD_PY_PROTECT_MODIFY)
      {
         int mi=Find(m_ops[i].id); if(mi<0) { Fault("modify thiếu member"); return false; }
         m_members[mi].requestedSl=stop;
      }
      if(!Save()) return false;
      long owner=kind==EXEC_CMD_PY_RH_TRIM ? (long)RecoveryMagic_ : (long)Magic;
      bool ok=false;
      if(kind==EXEC_CMD_PY_PROTECT_MODIFY)
      {
         double tp=PositionGetDouble(POSITION_TP);
         ok=m_exec.ModifySlTpOwned(ticket,stop,tp,owner,Key(d),
                                   EXEC_CMD_PY_PROTECT_MODIFY,EXEC_RECONCILE_FAIL_CLOSED);
      }
      else ok=m_exec.ClosePositionVolumeOwned(ticket,volume,owner,Key(d),
                           (eExecCommandType)kind,EXEC_RECONCILE_FAIL_CLOSED);
      if(!ok && !m_exec.HasReconcileRequired(Key(d)))
      {
         m_ops[i].complete=true;
         if(kind==EXEC_CMD_PY_PROTECT_MODIFY)
         { int mi=Find(m_ops[i].id); if(mi>=0) m_members[mi].requestedSl=m_members[mi].confirmedSl; }
         Save();
         Log_WarnEvery("PYProtect","reject"+(string)d,"T17.22 broker reject hiệu lực=0; giữ SL/obligation, retry",10);
      }
      m_basket.Invalidate(); m_historyDirty=true;
      return true;
   }
   bool SettleOperation()
   {
      int i=Pending(); if(i<0) return false;
      SPyProtectOperation op=m_ops[i];
      m_exec.ReconcileCycle(Key(op.dir));
      if(m_exec.HasReconcileRequired(Key(op.dir))) { Fault("request outcome ambiguous"); return true; }
      if(m_exec.HasPendingForCycle(Key(op.dir))) return true;
      double live=0;
      if(PositionSelectByTicket(op.ticket))
      {
         if((ulong)PositionGetInteger(POSITION_IDENTIFIER)!=op.id) { Fault("position identity changed"); return true; }
         live=PositionGetDouble(POSITION_VOLUME);
      }
      if(op.kind==EXEC_CMD_PY_PROTECT_MODIFY)
      {
         if(live>0)
         {
            double sl=PositionGetDouble(POSITION_SL);
            bool strong=op.dir==0 ? sl>=op.targetSl-m_tick*0.25 : sl<=op.targetSl+m_tick*0.25;
            if(sl<=0 || !strong) return true;
            int mi=Find(op.id); if(mi>=0) m_members[mi].confirmedSl=sl;
         }
         else m_group[op.dir].phase=PY_CLOSING;
      }
      else
      {
         double filled,cash;
         if(!OperationEffect(i,filled,cash)) return true;
         if(filled<=0 || live>op.beforeLots-filled+m_step*0.25) return true;
         string why="";
         if(!m_recovery.T1722FinalizePyMutation(*m_exec,Rdir(op.dir),TimeCurrent(),why))
         { if(why!="") Log_WarnEvery("PYProtect","refresh",why,10); return true; }
      }
      m_ops[i].complete=true; m_historyDirty=true; m_basket.Invalidate();
      if(op.kind==EXEC_CMD_PY_PROTECT_MODIFY)
      { for(int j=i+1;j<ArraySize(m_ops);j++) m_ops[j-1]=m_ops[j]; ArrayResize(m_ops,ArraySize(m_ops)-1); }
      Save();
      return true;
   }
   void FinishGroup(const int d)
   {
      long serial=m_group[d].serial;
      double net=m_snap[d].booked+m_group[d].trimCash;
      // Keep member SL tombstones for delayed broker callbacks; exclude old serials from economics.
      m_booked[d]=0;
      // Operation proof is retained for delayed callbacks/restart replay.
      ulong coreDeal=m_group[d].coreStartDeal;
      long coreMsc=m_group[d].coreStartMsc;
      double campaignCash=m_group[d].campaignTrimCash;
      ZeroMemory(m_group[d]); m_group[d].serial=serial;
      m_group[d].coreStartDeal=coreDeal; m_group[d].coreStartMsc=coreMsc;
      m_group[d].campaignTrimCash=campaignCash;
      m_basketRevision=0;
      Save();
      Log_Info("PYProtect","T17.22 "+(d==0 ? "BUY" : "SELL")+" | FLAT | đợt="+(string)serial+
               " | net settlement="+DoubleToString(net,2)+" | đợt mới tính lại từ fills mới");
   }

   bool ObserveSide(const EAContext &ctx,const int d,bool &changed)
   {
      if(m_snap[d].count>0 && m_group[d].phase==PY_EMPTY)
      {
         m_group[d].phase=PY_WATCH; m_group[d].mode=(int)PyramidSLMode_;
         m_group[d].serial++; m_group[d].peak=d==0 ? ctx.bid : ctx.ask; changed=true;
      }
      if(m_group[d].phase==PY_EMPTY) return true;
      double quote=d==0 ? ctx.bid : ctx.ask;
      double peak=PyProtect_StrongerPure(d,m_group[d].peak,quote);
      if(peak!=m_group[d].peak) m_group[d].peak=peak;
      double obligation=m_group[d].stop;
      if(m_group[d].phase==PY_PREPARE && m_group[d].candidate>0)
         obligation=PyProtect_StrongerPure(d,obligation,m_group[d].candidate);
      bool hit=PyProtect_HitPure(d,ctx.bid,ctx.ask,obligation);
      if(m_group[d].phase==PY_ARMED && m_snap[d].valid && NetAt(d,quote)<=m_group[d].floorCash)
         hit=true;
      if(hit)
      {
         if(m_group[d].phase!=PY_CLOSING) changed=true;
         m_group[d].phase=PY_CLOSING;
      }
      return true;
   }

   bool AllowsSlRequest(const MqlTradeRequest &req,const SExecRequestMeta &meta)
   {
      if(!OwnsSl(req.position)) return true;
      double current=PositionGetDouble(POSITION_SL);
      int d=(int)PositionGetInteger(POSITION_TYPE);
      if(current>0 && (req.sl<=0 || PyProtect_StrongerPure(d,current,req.sl)!=req.sl)) return false;
      return meta.commandType==EXEC_CMD_PY_PROTECT_MODIFY || MathAbs(req.sl-current)<m_tick*0.25;
   }
   bool ClassifyDeal(const MqlTradeRequest &req,const SExecRequestMeta &meta,
                     SPyProtectRequestView &view)
   {
      ZeroMemory(view);
      view.opening=req.position==0;
      view.dir=req.type==ORDER_TYPE_BUY ? 0 : 1;
      view.owner=meta.ownerMagic;
      if(!view.opening)
      {
         if(!PositionSelectByTicket(req.position)) return false;
         view.owner=PositionGetInteger(POSITION_MAGIC);
         view.dir=(int)PositionGetInteger(POSITION_TYPE);
         view.closingLots=MathMin(req.volume,PositionGetDouble(POSITION_VOLUME));
         view.pyramid=view.owner==(long)Magic && OC_IsPyramid(PositionGetString(POSITION_COMMENT));
      }
      else
         view.pyramid=view.owner==(long)Magic && OC_IsPyramid(req.comment);
      if(view.owner==(long)RecoveryMagic_) view.dir=1-view.dir;
      return view.dir>=0 && view.dir<=1;
   }
   bool CoordinateCorePeel(const MqlTradeRequest &req,const SExecRequestMeta &meta,
                           const SPyProtectRequestView &view)
   {
      bool matched=!view.opening && view.pyramid && meta.commandType==EXEC_CMD_CORE_PYRAMID_CLOSE &&
                   m_group[view.dir].phase!=PY_EMPTY;
      if(!matched) return true;
      long coreNow,hedgeNow,reservedNow;
      if(!Exposure(view.dir,coreNow,hedgeNow,reservedNow)) return false;
      long release=Recovery_VolumeToUnitsFloor(view.closingLots,m_step);
      long cap=PyProtect_CapUnitsPure(coreNow-release,reservedNow-release,CapPct());
      if(hedgeNow<=cap) return true;
      if(m_group[view.dir].releaseTicket!=0 && m_group[view.dir].releaseTicket!=req.position) return false;
      m_group[view.dir].releaseTicket=req.position;
      m_group[view.dir].releaseUnits=release;
      if(!Save()) return false;
      Log_Info("PYProtect","T17.22 "+(view.dir==0 ? "BUY" : "SELL")+
               " | PY EXIT WAIT RH | ticket="+(string)req.position+
               " | units="+(string)release);
      return false;
   }
   bool FundedPyramidAdd(const MqlTradeRequest &req,const int d)
   {
      m_basket.Update(m_context);
      Observe(m_context);
      if(!m_snap[d].valid || m_historyDirty || m_group[d].phase==PY_CLOSING) return false;
      double obligation=m_group[d].stop;
      if(m_group[d].phase==PY_PREPARE && m_group[d].candidate>0)
         obligation=PyProtect_StrongerPure(d,obligation,m_group[d].candidate);
      double extraCosts=req.volume*m_slope*(PyramidLockSafetyPips_*m_pip+Cfg.SlippagePrice);
      if(m_snap[d].lots>0) extraCosts+=2*m_snap[d].exitFees*req.volume/m_snap[d].lots;
      return PyProtect_AddFundedPure(d,obligation,req.price,req.volume,m_slope,
                                    NetAt(d,obligation),m_group[d].floorCash,extraCosts);
   }
   bool AllowsPreparedDeal(const MqlTradeRequest &req,const SPyProtectRequestView &view)
   {
      long core,hedge,reserved;
      if(!Exposure(view.dir,core,hedge,reserved)) return false;
      if(!view.opening && view.owner==(long)Magic)
      {
         long units=Recovery_VolumeToUnitsFloor(view.closingLots,m_step);
         core-=units;
         if(view.pyramid) reserved-=units;
      }
      if(view.opening && view.owner==(long)RecoveryMagic_)
         hedge+=Recovery_VolumeToUnitsFloor(req.volume,m_step);
      bool changesCap=(view.opening && view.owner==(long)RecoveryMagic_) ||
                      (!view.opening && view.owner==(long)Magic);
      if(changesCap && hedge>PyProtect_CapUnitsPure(core,reserved,CapPct())) return false;
      bool hasProtectionObligation=m_group[view.dir].stop>0 ||
         (m_group[view.dir].phase==PY_PREPARE && m_group[view.dir].candidate>0);
      if(view.opening && view.pyramid && hasProtectionObligation)
         return FundedPyramidAdd(req,view.dir);
      return true;
   }

   int DriveRelease(const int d,const EAContext &ctx)
   {
      if(m_group[d].releaseTicket==0) return PY_DRIVE_NEXT;
      if(!PositionSelectByTicket(m_group[d].releaseTicket))
      {
         string why="";
         if(!m_recovery.T1722FinalizePyMutation(*m_exec,Rdir(d),ctx.now,why)) return PY_DRIVE_BLOCK;
         m_group[d].releaseTicket=0; m_group[d].releaseUnits=0;
         m_historyDirty=true; m_basket.Invalidate(); Save();
         Log_Info("PYProtect","T17.22 "+(d==0 ? "BUY" : "SELL")+
                  " | PY EXIT SETTLED | tính lại snapshot từ fills mới");
         return PY_DRIVE_BLOCK;
      }
      if(m_exec.HasPendingMutation()) return PY_DRIVE_BLOCK;
      if(RecoveryMode_==recovery_ACTIVE && !m_recovery.T1722PyMutationQuiet(Rdir(d))) return PY_DRIVE_BLOCK;
      long coreNow,hedgeNow,reservedNow;
      if(!Exposure(d,coreNow,hedgeNow,reservedNow)) return PY_DRIVE_BLOCK;
      long release=MathMin(m_group[d].releaseUnits,reservedNow);
      long excess=hedgeNow-PyProtect_CapUnitsPure(coreNow-release,reservedNow-release,CapPct());
      if(excess<=0) return PY_DRIVE_ALLOW;
      ulong ticket; double lots,net;
      if(!SelectTrim(d,excess,ticket,lots,net)) return PY_DRIVE_BLOCK;
      return StartOperation(d,EXEC_CMD_PY_RH_TRIM,ticket,lots,0) ? PY_DRIVE_BLOCK : PY_DRIVE_ALLOW;
   }
   int DriveFlatSettlement(const int d,const EAContext &ctx)
   {
      if(m_snap[d].count!=0) return PY_DRIVE_NEXT;
      // Do not turn a Recovery fail-closed/pending interval into a per-tick
      // exposure scan. Settlement remains latched and resumes once both
      // mutation owners report a quiet, unambiguous topology.
      if(m_exec.HasPendingMutation()) return PY_DRIVE_BLOCK;
      if(RecoveryMode_==recovery_ACTIVE && !m_recovery.T1722PyMutationQuiet(Rdir(d)))
         return PY_DRIVE_BLOCK;
      // Broker SL can flatten PY before the EA gets a pre-close turn. Recompute
      // the live denominator and reduce RH first; only then rebase/finalize.
      long core,hedge,reserved;
      if(!Exposure(d,core,hedge,reserved)) return PY_DRIVE_BLOCK;
      long excess=hedge-PyProtect_CapUnitsPure(core,reserved,CapPct());
      if(excess>0)
      {
         ulong ticket; double lots,net;
         if(!SelectTrim(d,excess,ticket,lots,net)) return PY_DRIVE_BLOCK;
         return StartOperation(d,EXEC_CMD_PY_RH_TRIM,ticket,lots,0) ? PY_DRIVE_BLOCK : PY_DRIVE_ALLOW;
      }
      string why="";
      if(!m_recovery.T1722FinalizePyMutation(*m_exec,Rdir(d),ctx.now,why)) return PY_DRIVE_BLOCK;
      FinishGroup(d);
      return PY_DRIVE_BLOCK;
   }
   int DriveClosing(const int d)
   {
      if(m_group[d].phase!=PY_CLOSING) return PY_DRIVE_NEXT;
      long core,hedge,reserved;
      if(!Exposure(d,core,hedge,reserved)) return PY_DRIVE_BLOCK;
      long excess=hedge-PyProtect_CapUnitsPure(core,reserved,CapPct());
      if(excess>0)
      {
         ulong ticket; double lots,net;
         if(!SelectTrim(d,excess,ticket,lots,net)) return PY_DRIVE_BLOCK;
         return StartOperation(d,EXEC_CMD_PY_RH_TRIM,ticket,lots,0) ? PY_DRIVE_BLOCK : PY_DRIVE_ALLOW;
      }
      BasketSide side;
      if(d==0) side=m_basket.buy; else side=m_basket.sell;
      for(int i=side.count-1;i>=0;i--)
         if(side.pos[i].isPyramid)
         {
            return StartOperation(d,EXEC_CMD_PY_PROTECT_CLOSE,side.pos[i].ticket,side.pos[i].lots,0) ?
                   PY_DRIVE_BLOCK : PY_DRIVE_ALLOW;
         }
      return PY_DRIVE_BLOCK;
   }
   bool CandidateReady(const int d,const EAContext &ctx,double &candidate,
                       double &required,double &unitCash,double &distance)
   {
      unitCash=m_snap[d].lots*m_slope*m_pip;
      required=MathMax(m_group[d].floorCash,PyramidLockProfitPips_*unitCash);
      double funded=MathMax(required,PyramidLockProfitPips_*unitCash+MathMax(0.0,-m_group[d].trimCash));
      distance=m_tick;
      if(PyramidSLMode_==py_protect_BROKER)
         distance=MathMax(distance,(double)MathMax(SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL),
                                                   SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL))*m_point);
      if(m_group[d].phase==PY_PREPARE && m_group[d].candidate>0)
      {
         double coverage=PyProtect_LockPricePure(d,m_snap[d].weighted,m_snap[d].lots,
            m_snap[d].booked+m_snap[d].swap-Reserve(d,m_snap[d].lots),funded,m_slope,m_tick);
         candidate=PyProtect_StrongerPure(d,m_group[d].candidate,coverage);
         candidate=d==0 ? MathCeil(candidate/m_tick-1e-9)*m_tick : MathFloor(candidate/m_tick+1e-9)*m_tick;
         return PyProtect_ArmablePure(d,ctx.bid,ctx.ask,candidate,distance);
      }
      double trigger=PyramidBETriggerPips_*unitCash;
      if(m_group[d].phase==PY_WATCH &&
         m_snap[d].floating+m_snap[d].booked-Reserve(d,m_snap[d].lots)<trigger) return false;
      candidate=PyProtect_LockPricePure(d,m_snap[d].weighted,m_snap[d].lots,
         m_snap[d].booked+m_snap[d].swap-Reserve(d,m_snap[d].lots),funded,m_slope,m_tick);
      if(PyramidTrailGapPips_>0)
      {
         double trail=m_group[d].peak+(d==0 ? -1.0 : 1.0)*PyramidTrailGapPips_*m_pip;
         candidate=PyProtect_StrongerPure(d,candidate,trail);
      }
      candidate=PyProtect_StrongerPure(d,m_group[d].stop,candidate);
      candidate=d==0 ? MathCeil(candidate/m_tick-1e-9)*m_tick : MathFloor(candidate/m_tick+1e-9)*m_tick;
      return PyProtect_ArmablePure(d,ctx.bid,ctx.ask,candidate,distance);
   }
   int PrepareBeforeArm(const int d,const EAContext &ctx,const double required,
                        const double unitCash,const double distance)
   {
      if(m_group[d].phase==PY_ARMED) return PY_DRIVE_NEXT;
      long core,hedge,reserved;
      if(!Exposure(d,core,hedge,reserved)) return PY_DRIVE_BLOCK;
      long excess=hedge-PyProtect_CapUnitsPure(core,reserved,CapPct());
      if(excess<=0) return PY_DRIVE_NEXT;
      ulong ticket; double lots,net;
      if(!SelectTrim(d,excess,ticket,lots,net)) return PY_DRIVE_BLOCK;
      double funded=MathMax(required,PyramidLockProfitPips_*unitCash+
                            MathMax(0.0,-m_group[d].trimCash-net));
      double after=PyProtect_LockPricePure(d,m_snap[d].weighted,m_snap[d].lots,
         m_snap[d].booked+m_snap[d].swap-Reserve(d,m_snap[d].lots),funded,m_slope,m_tick);
      bool armable=PyProtect_ArmablePure(d,ctx.bid,ctx.ask,after,distance);
      ePyProtectPrepareDecision decision=PyProtect_PrepareDecisionPure(excess,true,armable);
      if(decision==PY_PREPARE_WAIT_UNFUNDED)
      {
         bool changed=m_group[d].phase!=PY_PREPARE || m_group[d].candidate!=after;
         m_group[d].phase=PY_PREPARE;
         m_group[d].candidate=PyProtect_StrongerPure(d,m_group[d].candidate,after);
         if(changed && !Save()) return PY_DRIVE_BLOCK;
         Log_WarnEvery("PYProtect","unfunded"+(string)d,
                       "T17.23 PREPARE WAIT: RH trim chưa được tài trợ; không ARM bằng candidate cũ",
                       Recovery_T165WaitLogSecondsPure(RecoveryWaitLogSeconds_));
         return PY_DRIVE_WAIT_UNFUNDED;
      }
      if(decision!=PY_PREPARE_TRIM_READY) return PY_DRIVE_BLOCK;
      m_group[d].phase=PY_PREPARE; m_group[d].candidate=after;
      if(!Save()) return PY_DRIVE_BLOCK;
      return StartOperation(d,EXEC_CMD_PY_RH_TRIM,ticket,lots,0) ? PY_DRIVE_BLOCK : PY_DRIVE_ALLOW;
   }
   int DriveBrokerStops(const int d,const double candidate)
   {
      if(PyramidSLMode_!=py_protect_BROKER) return PY_DRIVE_NEXT;
      BasketSide side;
      if(d==0) side=m_basket.buy; else side=m_basket.sell;
      for(int i=0;i<side.count;i++)
      {
         if(!side.pos[i].isPyramid || !PositionSelectByTicket(side.pos[i].ticket)) continue;
         double sl=PositionGetDouble(POSITION_SL);
         bool satisfied=sl>0 && (d==0 ? sl>=candidate-m_tick*0.25 : sl<=candidate+m_tick*0.25);
         if(satisfied) continue;
         if(m_group[d].phase==PY_WATCH) m_group[d].phase=PY_PREPARE;
         return StartOperation(d,EXEC_CMD_PY_PROTECT_MODIFY,side.pos[i].ticket,0,candidate) ?
                PY_DRIVE_BLOCK : PY_DRIVE_ALLOW;
      }
      return PY_DRIVE_NEXT;
   }
   int DriveSide(const int d,const EAContext &ctx)
   {
      if(!m_snap[d].valid) return PY_DRIVE_BLOCK;
      if(m_group[d].phase==PY_EMPTY) return PY_DRIVE_NEXT;
      if(m_group[d].phase==PY_CLOSING && m_group[d].releaseTicket!=0)
      { m_group[d].releaseTicket=0; m_group[d].releaseUnits=0; Save(); return PY_DRIVE_BLOCK; }
      int status=DriveRelease(d,ctx);
      if(status!=PY_DRIVE_NEXT) return status;
      status=DriveFlatSettlement(d,ctx);
      if(status!=PY_DRIVE_NEXT) return status;
      if(m_exec.HasPendingMutation())
         return m_group[d].phase==PY_CLOSING || m_group[d].phase==PY_PREPARE ? PY_DRIVE_BLOCK : PY_DRIVE_ALLOW;
      if(RecoveryMode_==recovery_ACTIVE && !m_recovery.T1722PyMutationQuiet(Rdir(d))) return PY_DRIVE_NEXT;
      status=DriveClosing(d);
      if(status!=PY_DRIVE_NEXT) return status;
      double candidate,required,unitCash,distance;
      if(!CandidateReady(d,ctx,candidate,required,unitCash,distance)) return PY_DRIVE_NEXT;
      status=PrepareBeforeArm(d,ctx,required,unitCash,distance);
      if(status!=PY_DRIVE_NEXT) return status;
      m_group[d].candidate=candidate;
      status=DriveBrokerStops(d,candidate);
      if(status!=PY_DRIVE_NEXT) return status;
      bool changed=m_group[d].phase!=PY_ARMED || m_group[d].stop!=candidate;
      m_group[d].phase=PY_ARMED; m_group[d].stop=candidate;
      m_group[d].floorCash=MathMax(required,NetAt(d,candidate));
      if(!changed) return PY_DRIVE_NEXT;
      if(!Save()) return PY_DRIVE_BLOCK;
      Log_Info("PYProtect","T17.22 "+(d==0 ? "BUY" : "SELL")+" | ARMED | đợt="+
         (string)m_group[d].serial+" | SL="+DoubleToString(candidate,_Digits)+
         " | net floor="+DoubleToString(m_group[d].floorCash,2));
      return PY_DRIVE_BLOCK;
   }

public:
   CPyramidProtection()
   {
      m_basket=NULL; m_exec=NULL; m_recovery=NULL; m_basketRevision=0;
      m_historyDirty=true; m_fault=false; m_recovered=false; m_override=false; m_nonce=0;
      m_observeCalls=0; m_rebinds=0; m_historyRefreshes=0;
      m_exposureScans=0; m_trimScans=0; m_scanVisits=0;
      for(int d=0;d<2;d++) { ZeroMemory(m_group[d]); ZeroMemory(m_snap[d]); m_booked[d]=0; }
   }
   bool Init(CBasketManager *basket,CExecutionLayer *exec,CRecoveryEngine *recovery)
   {
      m_basket=basket; m_exec=exec; m_recovery=recovery;
      m_tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
      m_step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
      m_pip=Recovery_PipSizePure(Sym_IsGold(),_Point,_Digits);
      m_point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
      m_file="BD_PYPROTECT_"+(string)AccountInfoInteger(ACCOUNT_LOGIN)+"_"+
             Recovery_SafeFileToken(_Symbol)+"_"+(string)Magic+".bin";
      if(!Enabled())
      {
         if(Persisted() && FileIsExist(m_file))
         { Log_Error("PYProtect","T17.22 state còn tồn tại; giữ mode/inputs để đối soát trước khi tắt"); return false; }
         return true;
      }
      if((int)PyramidSLMode_<1 || (int)PyramidSLMode_>2 || PyramidBETriggerPips_<0 ||
         PyramidLockProfitPips_<0 || PyramidLockSafetyPips_<=0 || PyramidTrailGapPips_<0 ||
         m_tick<=0 || m_step<=0 || m_pip<=0 || m_point<=0 ||
         AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING) return false;
      if(!Load()) { Fault("state identity/checksum/semantic mismatch"); return false; }
      g_pyramidProtection=GetPointer(this);
      return true;
   }
   void Observe(const EAContext &ctx)
   {
      if(!Enabled()) return;
      m_observeCalls++;
      m_context=ctx;
      double tv=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
      if(tv<=0 || m_tick<=0) { m_snap[0].valid=false; m_snap[1].valid=false; return; }
      m_slope=tv/m_tick;
      bool rebound=m_basketRevision!=m_basket.Revision();
      if(rebound)
      {
         m_rebinds++;
         if(!BindSide(m_basket.buy,0,m_buy) || !BindSide(m_basket.sell,1,m_sell)) return;
         m_basketRevision=m_basket.Revision();
      }
      if(m_historyDirty && !RefreshHistory())
      { m_snap[0].valid=false; m_snap[1].valid=false; return; }
      Snapshot(m_basket.buy,0,m_buy); Snapshot(m_basket.sell,1,m_sell);
      bool changed=rebound;
      for(int d=0;d<2;d++)
         if(!ObserveSide(ctx,d,changed)) return;
      if(changed) Save();
   }
   void OnTransaction(const MqlTradeTransaction &trans)
   {
      if(!Enabled() || trans.symbol!=_Symbol) return;
      if(trans.type==TRADE_TRANSACTION_DEAL_ADD || trans.type==TRADE_TRANSACTION_DEAL_UPDATE ||
         trans.type==TRADE_TRANSACTION_DEAL_DELETE)
      {
         m_historyDirty=true;
         if(trans.type==TRADE_TRANSACTION_DEAL_ADD && ExpectedPySl(trans.deal))
         {
            HistoryDealSelect(trans.deal);
            int i=Find((ulong)HistoryDealGetInteger(trans.deal,DEAL_POSITION_ID));
            if(i>=0 && m_members[i].serial==m_group[m_members[i].dir].serial &&
            m_group[m_members[i].dir].phase!=PY_EMPTY)
         { m_group[m_members[i].dir].phase=PY_CLOSING; Save(); }
         }
      }
   }
   string CloseComment(const int command,const ulong ticket)
   {
      int i=Pending();
      if(i>=0 && m_ops[i].kind==command && m_ops[i].ticket==ticket) return Tag(m_ops[i]);
      return "";
   }
   void SetExitOverride(const bool enabled) { m_override=enabled; }
   double CoordinationCash(const int dir) const
   { return Enabled() && dir>=0 && dir<2 ? m_group[dir].campaignTrimCash : 0.0; }
   bool ExpectedRhTrim(const ulong deal)
   {
      if(!Enabled() || deal==0) return false;
      for(int i=ArraySize(m_ops)-1;i>=0;i--)
         if(m_ops[i].kind==EXEC_CMD_PY_RH_TRIM && MatchesOperation(deal,m_ops[i])) return true;
      return false;
   }
   bool ExpectedPySl(const ulong deal)
   {
      if(!Enabled() || deal==0 || !HistoryDealSelect(deal) ||
         HistoryDealGetString(deal,DEAL_SYMBOL)!=_Symbol ||
         HistoryDealGetInteger(deal,DEAL_REASON)!=DEAL_REASON_SL) return false;
      int i=Find((ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID));
      if(i<0 || m_members[i].mode!=(int)py_protect_BROKER) return false;
      int d=m_members[i].dir;
      // FinishGroup intentionally retains the current-serial member as a
      // tombstone: MT5 may deliver another notification for the same deal
      // after the group is already FLAT. The next episode increments serial,
      // which makes this exact delayed proof ineligible without a phase guess.
      double programmed=HistoryDealGetDouble(deal,DEAL_SL);
      double confirmed=m_members[i].confirmedSl,requested=m_members[i].requestedSl;
      // A broker stop may execute on the same market event that acknowledged
      // the newest SL change, before SettleOperation promotes requestedSl to
      // confirmedSl. requestedSl was persisted before the broker side effect
      // and is rolled back to confirmedSl on a definitive reject, so the
      // exact programmed-price match is the durable proof in this window.
      return PyProtect_ExpectedBrokerSlPure(true,m_group[d].serial,m_members[i].serial,
                                            programmed,confirmed,requested,m_tick);
   }
   bool OwnsSl(const ulong ticket)
   {
      if(!Enabled() || !PositionSelectByTicket(ticket) || PositionGetString(POSITION_SYMBOL)!=_Symbol ||
         PositionGetInteger(POSITION_MAGIC)!=(long)Magic) return false;
      return OC_IsPyramid(PositionGetString(POSITION_COMMENT));
   }
   double PreserveSl(const ulong ticket,const double legacy)
   {
      if(!OwnsSl(ticket)) return legacy;
      return PositionGetDouble(POSITION_SL);
   }
   bool AllowsRequest(const MqlTradeRequest &req,const SExecRequestMeta &meta)
   {
      if(!Enabled() || req.symbol!=_Symbol || m_override) return true;
      if(req.action==TRADE_ACTION_SLTP) return AllowsSlRequest(req,meta);
      if(req.action!=TRADE_ACTION_DEAL) return true;
      SPyProtectRequestView view;
      if(!ClassifyDeal(req,meta,view)) return false;
      if(m_fault && view.opening) return false;
      bool ours=meta.commandType==EXEC_CMD_PY_PROTECT_CLOSE || meta.commandType==EXEC_CMD_PY_RH_TRIM;
      if(m_group[view.dir].phase==PY_CLOSING && !ours) return false;
      if(view.owner!=(long)Magic && view.owner!=(long)RecoveryMagic_) return true;
      if(m_group[view.dir].releaseTicket!=0 && !ours &&
         (view.opening || req.position!=m_group[view.dir].releaseTicket)) return false;

      // CorePyramid LIFO peel is a standalone PY exit outside the generic
      // Recovery full-side coordinator. Persist its intended post-close
      // denominator, trim RH first when needed, then admit the exact retry.
      if(!CoordinateCorePeel(req,meta,view)) return false;
      if(m_group[view.dir].phase<PY_PREPARE) return true;
      return AllowsPreparedDeal(req,view);
   }
   bool Drive(const EAContext &ctx)
   {
      if(!Enabled()) return false;
      if(m_fault) return true;
      if(SettleOperation()) return true;
      if(m_historyDirty) return true;
      for(int d=0;d<2;d++)
      {
         int status=DriveSide(d,ctx);
         if(status==PY_DRIVE_ALLOW || status==PY_DRIVE_WAIT_UNFUNDED) return false;
         if(status==PY_DRIVE_BLOCK) return true;
      }
      return false;
   }

   void ReportPerformance()
   {
      if(!Enabled()) return;
      Log_Info("PYProtect","T17.22 PERF | observe="+(string)m_observeCalls+
               " | rebind="+(string)m_rebinds+
               " | history="+(string)m_historyRefreshes+
               " | exposure="+(string)m_exposureScans+
               " | trim="+(string)m_trimScans+
               " | position_visits="+(string)m_scanVisits);
   }
};
#endif
