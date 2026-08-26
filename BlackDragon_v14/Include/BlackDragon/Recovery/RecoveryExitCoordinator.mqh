//+------------------------------------------------------------------+
//| RecoveryExitCoordinator.mqh — T17.9 REAL broker TP wrapper      |
//| Base T17.7/T16 coordinator remains byte-identical in T177Base.   |
//| Expected Core broker TP is never misclassified as manual/external.|
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_EXIT_COORDINATOR_T178_WRAPPER_MQH
#define BD_RECOVERY_EXIT_COORDINATOR_T178_WRAPPER_MQH

#include "RecoveryExitCoordinatorT177Base.mqh"
#include "RecoveryT178RuntimePolicy.mqh"
#include "RecoveryT179RealTpPolicy.mqh"
#include <BlackDragon/Config.mqh>

#define BD_T178_TP_MAGIC   0x38505452 // "RTP8"
#define BD_T178_TP_VERSION 2
#define BD_T179_TP_COHORT_CAP 64
// Legacy T17.8 source-contract anchor: BD_T178_TP_VERSION 1

struct SRecoveryT178TpPersistHeader
{
   uint magic;
   uint version;
   uint payloadSize;
   uint checksum;
};

struct SRecoveryT178TpPersistIdentity
{
   long accountLogin;
   uint symbolHash;
   long coreMagic;
   long recoveryMagic;
   long saveSequence;
};

struct SRecoveryT178TpEpoch
{
   int active;
   int dir;
   int recoveryOwned;
   int settling;
   double targetTp;
   datetime startedAt;
   datetime updatedAt;
   int cohortCount;
   ulong positionIds[BD_T179_TP_COHORT_CAP];
};

uint Recovery_T178FnvBytes(const uchar &bytes[])
{
   uint h = 2166136261;
   for(int i=0;i<ArraySize(bytes);i++)
   {
      h ^= (uint)bytes[i];
      h *= 16777619;
   }
   return h;
}

class CRecoveryExitCoordinatorT178 : public CRecoveryExitCoordinator
{
private:
   SRecoveryT178TpEpoch m_tpEpoch[2];
   string               m_tpFile;
   string               m_tpTemp;
   long                 m_tpSaveSequence;
   bool                 m_tpPersistenceFault;

   int T178Index(const eRecoveryCoreDirection dir) const
   {
      return dir == recovery_CORE_BUY ? 0 : 1;
   }

   eRecoveryCoreDirection T178Direction(const int idx) const
   {
      return idx == 0 ? recovery_CORE_BUY : recovery_CORE_SELL;
   }

   long T178CorePositionType(const eRecoveryCoreDirection dir) const
   {
      return dir == recovery_CORE_BUY ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   }

   long T178RecoveryPositionType(const eRecoveryCoreDirection dir) const
   {
      return dir == recovery_CORE_BUY ? POSITION_TYPE_SELL : POSITION_TYPE_BUY;
   }

   bool T179RecoveryOwnsSide(const eRecoveryCoreDirection dir) const
   {
      return CycleRequiresCoordination(dir);
   }

   bool T179EpochContains(const int idx,const ulong positionId) const
   {
      if(positionId==0 || idx<0 || idx>1) return false;
      int n=m_tpEpoch[idx].cohortCount;
      if(n<0 || n>BD_T179_TP_COHORT_CAP) return false;
      for(int i=0;i<n;i++) if(m_tpEpoch[idx].positionIds[i]==positionId) return true;
      return false;
   }

   void T179InsertPositionId(SRecoveryT178TpEpoch &epoch,const ulong positionId)
   {
      int n=epoch.cohortCount;
      if(positionId==0 || n<0 || n>=BD_T179_TP_COHORT_CAP) return;
      int at=n;
      while(at>0 && epoch.positionIds[at-1]>positionId)
      {
         epoch.positionIds[at]=epoch.positionIds[at-1];
         at--;
      }
      if(at>0 && epoch.positionIds[at-1]==positionId) return;
      if(at<n && epoch.positionIds[at]==positionId) return;
      epoch.positionIds[at]=positionId;
      epoch.cohortCount=n+1;
   }

   bool T179CaptureCoreCohort(const eRecoveryCoreDirection dir,
                              const double targetTp,
                              const datetime now,
                              SRecoveryT178TpEpoch &epoch,
                              string &why) const
   {
      why="";
      ZeroMemory(epoch);
      epoch.active=1;
      epoch.dir=(int)dir;
      epoch.recoveryOwned=T179RecoveryOwnsSide(dir) ? 1 : 0;
      epoch.targetTp=targetTp;
      epoch.startedAt=now;
      epoch.updatedAt=now;
      long wanted=T178CorePositionType(dir);
      for(int i=PositionsTotal()-1;i>=0;i--)
      {
         ulong ticket=PositionGetTicket(i);
         if(ticket==0) continue;
         if(PositionGetString(POSITION_SYMBOL)!=_Symbol ||
            PositionGetInteger(POSITION_MAGIC)!=(long)Magic ||
            PositionGetInteger(POSITION_TYPE)!=wanted) continue;
         ulong positionId=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
         if(positionId==0) { why="Core position thiếu POSITION_IDENTIFIER"; return false; }
         if(epoch.cohortCount>=BD_T179_TP_COHORT_CAP)
         { why="REAL TP cohort vượt capacity an toàn"; return false; }
         // Inline sorted insert keeps persisted identity deterministic.
         int at=epoch.cohortCount;
         while(at>0 && epoch.positionIds[at-1]>positionId)
         { epoch.positionIds[at]=epoch.positionIds[at-1]; at--; }
         if((at>0 && epoch.positionIds[at-1]==positionId) ||
            (at<epoch.cohortCount && epoch.positionIds[at]==positionId)) continue;
         epoch.positionIds[at]=positionId;
         epoch.cohortCount++;
      }
      if(epoch.cohortCount<=0) { why="không có exact-Magic Core để tạo epoch"; return false; }
      return true;
   }

   bool T179SameEpoch(const SRecoveryT178TpEpoch &a,
                      const SRecoveryT178TpEpoch &b) const
   {
      double tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
      if(tick<=0.0) tick=_Point;
      if(a.active!=b.active || a.dir!=b.dir || a.recoveryOwned!=b.recoveryOwned ||
         a.settling!=b.settling || a.cohortCount!=b.cohortCount ||
         MathAbs(a.targetTp-b.targetTp)>MathMax(tick,_Point)+1e-12) return false;
      for(int i=0;i<a.cohortCount;i++) if(a.positionIds[i]!=b.positionIds[i]) return false;
      return true;
   }

   void ResetTpEpoch(const int idx)
   {
      ZeroMemory(m_tpEpoch[idx]);
      m_tpEpoch[idx].dir = (int)T178Direction(idx);
   }

   uint TpPayloadSize() const
   {
      return (uint)(sizeof(SRecoveryT178TpPersistIdentity) +
                    2 * sizeof(SRecoveryT178TpEpoch));
   }

   bool ReadTpPayloadRaw(const int handle, uchar &raw[], string &why) const
   {
      uint size = TpPayloadSize();
      ArrayResize(raw,(int)size);
      if(!FileSeek(handle,(long)sizeof(SRecoveryT178TpPersistHeader),SEEK_SET))
      { why="không seek được payload REAL TP"; return false; }
      uint n=FileReadArray(handle,raw,0,(int)size);
      if(n!=size) { why="payload REAL TP thiếu byte"; return false; }
      return true;
   }

   bool AnyTpEpoch() const
   {
      return m_tpEpoch[0].active != 0 || m_tpEpoch[1].active != 0;
   }

   bool SaveTpEpochs(string &why)
   {
      why="";
      if(MQLInfoInteger(MQL_TESTER) && !RecoveryTesterResumeState_) return true;
      if(m_tpFile=="") { why="persistence REAL TP chưa khởi tạo"; return false; }
      if(!AnyTpEpoch())
      {
         FileDelete(m_tpTemp);
         FileDelete(m_tpFile);
         return true;
      }

      SRecoveryT178TpPersistHeader header;
      header.magic=BD_T178_TP_MAGIC;
      header.version=BD_T178_TP_VERSION;
      header.payloadSize=TpPayloadSize();
      header.checksum=0;

      SRecoveryT178TpPersistIdentity identity;
      ZeroMemory(identity);
      identity.accountLogin=AccountInfoInteger(ACCOUNT_LOGIN);
      identity.symbolHash=Recovery_Fnv1aTextPure(_Symbol);
      identity.coreMagic=(long)Magic;
      identity.recoveryMagic=(long)RecoveryMagic_;
      identity.saveSequence=++m_tpSaveSequence;

      FileDelete(m_tpTemp);
      int h=FileOpen(m_tpTemp,FILE_WRITE|FILE_BIN);
      if(h==INVALID_HANDLE) { why="không tạo được temp REAL TP"; return false; }
      bool ok=FileWriteStruct(h,header)==sizeof(SRecoveryT178TpPersistHeader) &&
              FileWriteStruct(h,identity)==sizeof(SRecoveryT178TpPersistIdentity) &&
              FileWriteStruct(h,m_tpEpoch[0])==sizeof(SRecoveryT178TpEpoch) &&
              FileWriteStruct(h,m_tpEpoch[1])==sizeof(SRecoveryT178TpEpoch);
      FileFlush(h); FileClose(h);
      if(!ok) { FileDelete(m_tpTemp); why="ghi state REAL TP thiếu byte"; return false; }

      h=FileOpen(m_tpTemp,FILE_READ|FILE_BIN);
      if(h==INVALID_HANDLE) { FileDelete(m_tpTemp); why="không mở lại temp REAL TP"; return false; }
      uchar raw[];
      if(!ReadTpPayloadRaw(h,raw,why)) { FileClose(h); FileDelete(m_tpTemp); return false; }
      FileClose(h);
      header.checksum=Recovery_T178FnvBytes(raw);

      h=FileOpen(m_tpTemp,FILE_READ|FILE_WRITE|FILE_BIN);
      if(h==INVALID_HANDLE) { FileDelete(m_tpTemp); why="không finalize được temp REAL TP"; return false; }
      if(!FileSeek(h,0,SEEK_SET) ||
         FileWriteStruct(h,header)!=sizeof(SRecoveryT178TpPersistHeader))
      { FileClose(h); FileDelete(m_tpTemp); why="không finalize header REAL TP"; return false; }
      FileFlush(h);
      ulong finalSize=FileSize(h);
      FileClose(h);
      ulong expected=(ulong)sizeof(SRecoveryT178TpPersistHeader)+(ulong)TpPayloadSize();
      if(finalSize!=expected) { FileDelete(m_tpTemp); why="kích thước state REAL TP sai"; return false; }
      if(!FileMove(m_tpTemp,0,m_tpFile,FILE_REWRITE))
      { FileDelete(m_tpTemp); why="atomic replace state REAL TP thất bại"; return false; }
      return true;
   }

   bool LoadTpEpochs(string &why)
   {
      why="";
      if(!Recovery_ShouldReusePersistedStatePure((bool)MQLInfoInteger(MQL_TESTER),
                                                 RecoveryTesterResumeState_))
         return true;
      if(!FileIsExist(m_tpFile)) return true;
      int h=FileOpen(m_tpFile,FILE_READ|FILE_BIN);
      if(h==INVALID_HANDLE) { why="không mở được state REAL TP"; return false; }
      ulong expected=(ulong)sizeof(SRecoveryT178TpPersistHeader)+(ulong)TpPayloadSize();
      if(FileSize(h)!=expected) { FileClose(h); why="kích thước state REAL TP sai schema"; return false; }

      SRecoveryT178TpPersistHeader header;
      if(FileReadStruct(h,header)!=sizeof(SRecoveryT178TpPersistHeader) ||
         header.magic!=BD_T178_TP_MAGIC || header.version!=BD_T178_TP_VERSION ||
         header.payloadSize!=TpPayloadSize())
      { FileClose(h); why="header/version state REAL TP không hợp lệ"; return false; }
      uchar raw[];
      if(!ReadTpPayloadRaw(h,raw,why)) { FileClose(h); return false; }
      if(Recovery_T178FnvBytes(raw)!=header.checksum)
      { FileClose(h); why="checksum state REAL TP không khớp"; return false; }
      if(!FileSeek(h,(long)sizeof(SRecoveryT178TpPersistHeader),SEEK_SET))
      { FileClose(h); why="không seek được state REAL TP"; return false; }
      SRecoveryT178TpPersistIdentity identity;
      SRecoveryT178TpEpoch e0,e1;
      if(FileReadStruct(h,identity)!=sizeof(SRecoveryT178TpPersistIdentity) ||
         FileReadStruct(h,e0)!=sizeof(SRecoveryT178TpEpoch) ||
         FileReadStruct(h,e1)!=sizeof(SRecoveryT178TpEpoch))
      { FileClose(h); why="decode state REAL TP thất bại"; return false; }
      FileClose(h);
      if(identity.accountLogin!=AccountInfoInteger(ACCOUNT_LOGIN) ||
         identity.symbolHash!=Recovery_Fnv1aTextPure(_Symbol) ||
         identity.coreMagic!=(long)Magic || identity.recoveryMagic!=(long)RecoveryMagic_)
      { why="identity state REAL TP không khớp runtime"; return false; }
      if((e0.active!=0 && e0.dir!=(int)recovery_CORE_BUY) ||
         (e1.active!=0 && e1.dir!=(int)recovery_CORE_SELL))
      { why="side state REAL TP không hợp lệ"; return false; }
      if(e0.cohortCount<0 || e0.cohortCount>BD_T179_TP_COHORT_CAP ||
         e1.cohortCount<0 || e1.cohortCount>BD_T179_TP_COHORT_CAP)
      { why="cohort count state REAL TP không hợp lệ"; return false; }
      if((e0.active!=0 && (e0.targetTp<=0.0 || e0.cohortCount<=0)) ||
         (e1.active!=0 && (e1.targetTp<=0.0 || e1.cohortCount<=0)))
      { why="epoch REAL TP thiếu target/cohort"; return false; }
      m_tpEpoch[0]=e0; m_tpEpoch[1]=e1;
      m_tpSaveSequence=identity.saveSequence;
      return true;
   }

   long ResolveClosedOwnerMagicT178(const ulong closingDeal) const
   {
      if(closingDeal==0 || !HistoryDealSelect(closingDeal)) return 0;
      long direct=HistoryDealGetInteger(closingDeal,DEAL_MAGIC);
      if(direct==(long)Magic || direct==(long)RecoveryMagic_) return direct;
      ulong positionId=(ulong)HistoryDealGetInteger(closingDeal,DEAL_POSITION_ID);
      if(positionId==0 || !HistorySelectByPosition(positionId)) return direct;
      long owner=direct;
      long bestMsc=0;
      for(int i=0;i<HistoryDealsTotal();i++)
      {
         ulong deal=HistoryDealGetTicket(i);
         if(deal==0 || HistoryDealGetString(deal,DEAL_SYMBOL)!=_Symbol) continue;
         long entry=HistoryDealGetInteger(deal,DEAL_ENTRY);
         if(entry!=DEAL_ENTRY_IN && entry!=DEAL_ENTRY_INOUT) continue;
         long msc=HistoryDealGetInteger(deal,DEAL_TIME_MSC);
         if(bestMsc==0 || msc<bestMsc)
         { bestMsc=msc; owner=HistoryDealGetInteger(deal,DEAL_MAGIC); }
      }
      return owner;
   }

   bool MapCoreClosingDealT178(const long ownerMagic,
                               const long dealType,
                               eRecoveryCoreDirection &dir) const
   {
      if(ownerMagic!=(long)Magic) return false;
      if(dealType==DEAL_TYPE_SELL) { dir=recovery_CORE_BUY; return true; }
      if(dealType==DEAL_TYPE_BUY)  { dir=recovery_CORE_SELL; return true; }
      return false;
   }

   double ProgrammedTpFromDealT178(const ulong deal) const
   {
      if(deal==0 || !HistoryDealSelect(deal)) return 0.0;
      double tp=HistoryDealGetDouble(deal,DEAL_TP);
      if(tp>0.0) return tp;
      ulong order=(ulong)HistoryDealGetInteger(deal,DEAL_ORDER);
      if(order!=0 && HistoryOrderSelect(order))
         tp=HistoryOrderGetDouble(order,ORDER_TP);
      HistoryDealSelect(deal);
      return tp;
   }

   bool LiveCoreTpCohortMatchesT178(const eRecoveryCoreDirection dir,
                                    const double programmedTp,
                                    const double tolerance) const
   {
      long wanted=T178CorePositionType(dir);
      for(int i=PositionsTotal()-1;i>=0;i--)
      {
         ulong ticket=PositionGetTicket(i);
         if(ticket==0) continue;
         if(PositionGetString(POSITION_SYMBOL)!=_Symbol ||
            PositionGetInteger(POSITION_MAGIC)!=(long)Magic ||
            PositionGetInteger(POSITION_TYPE)!=wanted)
            continue;
         double tp=PositionGetDouble(POSITION_TP);
         if(tp<=0.0 || MathAbs(tp-programmedTp)>tolerance+1e-12)
            return false;
      }
      return true;
   }

   eRecoveryT179RealTpProof ClassifyCoreRealTpDealT179(
                                   const eRecoveryCoreDirection dir,
                                   const ulong deal,
                                   bool &strictProof) const
   {
      strictProof=false;
      if(deal==0 || !HistoryDealSelect(deal)) return RECOVERY_T179_TP_EXTERNAL;
      long owner=ResolveClosedOwnerMagicT178(deal);
      if(!HistoryDealSelect(deal)) return RECOVERY_T179_TP_EXTERNAL;
      long reason=HistoryDealGetInteger(deal,DEAL_REASON);
      double dealPrice=HistoryDealGetDouble(deal,DEAL_PRICE);
      double programmedTp=ProgrammedTpFromDealT178(deal);
      if(!HistoryDealSelect(deal)) return RECOVERY_T179_TP_EXTERNAL;
      ulong positionId=(ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID);
      double tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
      double spread=(double)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD)*_Point;
      if(tick<=0.0) return RECOVERY_T179_TP_EXTERNAL;
      double tpTolerance=MathMax(2.0*tick,_Point);
      double fillTolerance=MathMax(500.0*tick,5.0*spread+5.0*tick);
      strictProof=Recovery_T179StrictBrokerTpProofPure(TP_Mode==mode_Real,
                                                        Cfg.TP!=0,
                                                        owner==(long)Magic,
                                                        reason==DEAL_REASON_TP,
                                                        programmedTp,
                                                        dealPrice,
                                                        fillTolerance);
      int idx=T178Index(dir);
      bool epochActive=m_tpEpoch[idx].active!=0;
      bool targetMatches=epochActive &&
         MathAbs(m_tpEpoch[idx].targetTp-programmedTp)<=tpTolerance+1e-12;
      bool idMatches=epochActive && T179EpochContains(idx,positionId);
      return Recovery_T179ClassifyBrokerTpPure(strictProof,
                                                T179RecoveryOwnsSide(dir),
                                                epochActive,
                                                targetMatches,
                                                idMatches);
   }

   long CoreUnitsT178(const eRecoveryCoreDirection dir) const
   {
      long units=0;
      double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
      long wanted=T178CorePositionType(dir);
      if(step<=0.0) return 0;
      for(int i=PositionsTotal()-1;i>=0;i--)
      {
         ulong ticket=PositionGetTicket(i);
         if(ticket==0) continue;
         if(PositionGetString(POSITION_SYMBOL)!=_Symbol ||
            PositionGetInteger(POSITION_MAGIC)!=(long)Magic ||
            PositionGetInteger(POSITION_TYPE)!=wanted) continue;
         units+=Recovery_VolumeToUnitsFloor(PositionGetDouble(POSITION_VOLUME),step);
      }
      return units;
   }

   long RecoveryUnitsT178(const eRecoveryCoreDirection dir) const
   {
      long units=0;
      double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
      long wanted=T178RecoveryPositionType(dir);
      if(step<=0.0) return 0;
      for(int i=PositionsTotal()-1;i>=0;i--)
      {
         ulong ticket=PositionGetTicket(i);
         if(ticket==0) continue;
         if(PositionGetString(POSITION_SYMBOL)!=_Symbol ||
            PositionGetInteger(POSITION_MAGIC)!=(long)RecoveryMagic_ ||
            PositionGetInteger(POSITION_TYPE)!=wanted) continue;
         units+=Recovery_VolumeToUnitsFloor(PositionGetDouble(POSITION_VOLUME),step);
      }
      return units;
   }

   bool StorePreparedTpEpochT179(const eRecoveryCoreDirection dir,
                                const double targetTp,
                                const datetime now,
                                string &why)
   {
      int idx=T178Index(dir);
      if(m_tpEpoch[idx].active!=0 && m_tpEpoch[idx].settling!=0) return true;
      SRecoveryT178TpEpoch next;
      if(!T179CaptureCoreCohort(dir,targetTp,now,next,why)) return false;
      if(T179SameEpoch(m_tpEpoch[idx],next)) return true;
      SRecoveryT178TpEpoch old=m_tpEpoch[idx];
      m_tpEpoch[idx]=next;
      if(SaveTpEpochs(why)) return true;
      m_tpEpoch[idx]=old;
      return false;
   }

   bool MarkTpEpochSettlingT179(const eRecoveryCoreDirection dir,
                               const ulong positionId,
                               const double targetTp,
                               const datetime now,
                               string &why)
   {
      int idx=T178Index(dir);
      SRecoveryT178TpEpoch old=m_tpEpoch[idx];
      if(m_tpEpoch[idx].active==0)
      {
         if(!T179CaptureCoreCohort(dir,targetTp,now,m_tpEpoch[idx],why))
         {
            // The first callback may arrive after the broker already removed
            // every live member. Preserve at least the immutable deal identity.
            ResetTpEpoch(idx);
            m_tpEpoch[idx].active=1;
            m_tpEpoch[idx].dir=(int)dir;
            m_tpEpoch[idx].recoveryOwned=T179RecoveryOwnsSide(dir) ? 1 : 0;
            m_tpEpoch[idx].targetTp=targetTp;
            m_tpEpoch[idx].startedAt=now;
            m_tpEpoch[idx].updatedAt=now;
            m_tpEpoch[idx].cohortCount=0;
         }
      }
      if(positionId!=0 && !T179EpochContains(idx,positionId))
         T179InsertPositionId(m_tpEpoch[idx],positionId);
      if(m_tpEpoch[idx].cohortCount<=0)
      { m_tpEpoch[idx]=old; why="không khóa được identifier cho epoch REAL TP"; return false; }
      m_tpEpoch[idx].targetTp=targetTp;
      m_tpEpoch[idx].settling=1;
      m_tpEpoch[idx].updatedAt=now;
      if(SaveTpEpochs(why)) return true;
      m_tpEpoch[idx]=old;
      return false;
   }

   void MaybeCompleteTpEpoch(const eRecoveryCoreDirection dir)
   {
      int idx=T178Index(dir);
      if(m_tpEpoch[idx].active==0) return;
      if(m_tpEpoch[idx].settling==0)
      {
         if(CoreUnitsT178(dir)>0) return;
      }
      else if(!Recovery_T179SettlementCompletePure(true,true,CoreUnitsT178(dir),
                                                    RecoveryUnitsT178(dir),
                                                    ReconcileHold(dir))) return;
      ResetTpEpoch(idx);
      string why="";
      if(!SaveTpEpochs(why))
      {
         m_tpPersistenceFault=true;
         Log_Error("Recovery","LỖI "+Recovery_DirectionName(dir)+
                   " | Không lưu được trạng thái kết thúc REAL TP | "+why);
      }
      else
         Log_Info("Recovery","TP THẬT "+Recovery_DirectionName(dir)+
                  " | Core/Hedge đã về trạng thái an toàn | kết thúc chu kỳ TP broker");
   }

public:
   CRecoveryExitCoordinatorT178(void) : CRecoveryExitCoordinator()
   {
      ResetTpEpoch(0); ResetTpEpoch(1);
      m_tpFile=""; m_tpTemp=""; m_tpSaveSequence=0;
      m_tpPersistenceFault=false;
   }

   void Init(CRecoveryEngine *recovery, CExecutionLayer *exec)
   {
      CRecoveryExitCoordinator::Init(recovery,exec);
      ResetTpEpoch(0); ResetTpEpoch(1);
      m_tpSaveSequence=0;
      m_tpPersistenceFault=false;
      string token=Recovery_SafeFileToken(_Symbol);
      m_tpFile="BD_T179_REALTP_"+(string)AccountInfoInteger(ACCOUNT_LOGIN)+"_"+
               token+"_"+(string)Magic+"_"+(string)RecoveryMagic_+".bin";
      m_tpTemp=m_tpFile+".tmp";
      string why="";
      if(!LoadTpEpochs(why))
      {
         m_tpPersistenceFault=true;
         Log_Error("Recovery","LỖI | Không đọc được state REAL TP | "+why);
         return;
      }
      for(int i=0;i<2;i++)
      {
         if(m_tpEpoch[i].active==0) continue;
         eRecoveryCoreDirection dir=T178Direction(i);
         if(m_tpEpoch[i].settling==0)
         {
            if(CoreUnitsT178(dir)<=0) ResetTpEpoch(i);
            continue;
         }
         eRecoveryExitCoordRequest req=CRecoveryExitCoordinator::BeginFullSideClose(
            dir,recovery_EXIT_REASON_LEGACY_TP,m_tpEpoch[i].startedAt);
         if(req==recovery_EXIT_BYPASS && CoreUnitsT178(dir)<=0 && RecoveryUnitsT178(dir)<=0)
         {
            ResetTpEpoch(i);
            continue;
         }
         Log_Info("Recovery","TP THẬT "+Recovery_DirectionName(dir)+
                  " | Khôi phục chu kỳ chốt broker sau restart | tiếp tục dọn Core/Hedge");
      }
      if(!SaveTpEpochs(why))
      {
         m_tpPersistenceFault=true;
         Log_Error("Recovery","LỖI | Không cập nhật được state REAL TP sau khởi động | "+why);
      }
   }

   bool PrepareRealTpEpoch(const eRecoveryCoreDirection dir,
                           const double targetTp,
                           const datetime now)
   {
      if(RecoveryMode_!=recovery_ACTIVE || TP_Mode!=mode_Real || Cfg.TP==0)
         return true;
      if(targetTp<=0.0) return true;
      int idx=T178Index(dir);
      if(CoreUnitsT178(dir)<=0)
      {
         if(m_tpEpoch[idx].active==0 || m_tpEpoch[idx].settling!=0) return true;
         SRecoveryT178TpEpoch old=m_tpEpoch[idx];
         ResetTpEpoch(idx);
         string clearWhy="";
         if(SaveTpEpochs(clearWhy)) return true;
         m_tpEpoch[idx]=old;
         m_tpPersistenceFault=true;
         Log_Error("Recovery","LỖI "+Recovery_DirectionName(dir)+
                   " | Không xóa được epoch REAL TP đã flat | "+clearWhy);
         return false;
      }
      string why="";
      if(StorePreparedTpEpochT179(dir,targetTp,now,why)) return true;
      m_tpPersistenceFault=true;
      Log_Error("Recovery","LỖI "+Recovery_DirectionName(dir)+
                " | Không chuẩn bị được epoch REAL TP trước mutation | "+why);
      return false;
   }

   bool ObserveRealTpSettlement(const eRecoveryCoreDirection dir,
                                const double bid,
                                const double ask,
                                const datetime now)
   {
      if(RecoveryMode_!=recovery_ACTIVE || TP_Mode!=mode_Real || Cfg.TP==0)
         return false;
      int idx=T178Index(dir);
      if(m_tpEpoch[idx].active==0)
      {
         // Covers restart/upgrade and the first tick after positions appeared:
         // snapshot the broker-programmed exact-Magic cohort before any ADD.
         double commonTp=0.0;
         double tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
         if(tick<=0.0) tick=_Point;
         long wanted=T178CorePositionType(dir);
         bool mismatch=false;
         for(int i=PositionsTotal()-1;i>=0;i--)
         {
            ulong ticket=PositionGetTicket(i);
            if(ticket==0 || PositionGetString(POSITION_SYMBOL)!=_Symbol ||
               PositionGetInteger(POSITION_MAGIC)!=(long)Magic ||
               PositionGetInteger(POSITION_TYPE)!=wanted) continue;
            double tp=PositionGetDouble(POSITION_TP);
            if(tp<=0.0) { mismatch=true; break; }
            if(commonTp<=0.0) commonTp=tp;
            else if(MathAbs(commonTp-tp)>MathMax(2.0*tick,_Point)+1e-12)
            { mismatch=true; break; }
         }
         if(!mismatch && commonTp>0.0 && !PrepareRealTpEpoch(dir,commonTp,now))
            return true;
      }
      if(m_tpEpoch[idx].active==0 || m_tpEpoch[idx].settling!=0)
         return m_tpEpoch[idx].settling!=0;
      double tolerance=MathMax(2.0*SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE),_Point);
      bool hit=dir==recovery_CORE_BUY ? bid+tolerance>=m_tpEpoch[idx].targetTp :
                                       ask-tolerance<=m_tpEpoch[idx].targetTp;
      if(!Recovery_T179SettlementStartsPure(true,false,hit,false)) return false;
      string why="";
      if(!MarkTpEpochSettlingT179(dir,0,m_tpEpoch[idx].targetTp,now,why))
      {
         m_tpPersistenceFault=true;
         Log_Error("Recovery","LỖI "+Recovery_DirectionName(dir)+
                   " | Không khóa được settlement barrier REAL TP | "+why);
         return true;
      }
      Log_Info("Recovery","TP THẬT "+Recovery_DirectionName(dir)+
               " | Giá đã chạm cohort broker TP | khóa ADD cùng side tới khi settle xong");
      return true;
   }

   bool BlocksSameSideAdd(const eRecoveryCoreDirection dir) const
   {
      int idx=T178Index(dir);
      return Recovery_T179BlocksSameSideAddPure(m_tpPersistenceFault,
                                                 m_tpEpoch[idx].settling!=0);
   }

   bool HasBlockingWork() const
   {
      return m_tpPersistenceFault || CRecoveryExitCoordinator::HasBlockingWork();
   }

   bool Drive(const datetime now, string &why)
   {
      if(m_tpPersistenceFault)
      {
         why="state REAL TP lỗi; giữ fail-closed";
         return true;
      }
      bool blocking=CRecoveryExitCoordinator::Drive(now,why);
      MaybeCompleteTpEpoch(recovery_CORE_BUY);
      MaybeCompleteTpEpoch(recovery_CORE_SELL);
      return blocking || HasBlockingWork();
   }

   bool OnTradeTransaction(const MqlTradeTransaction &trans)
   {
      if(RecoveryMode_==recovery_ACTIVE &&
         trans.type==TRADE_TRANSACTION_DEAL_ADD && trans.deal!=0 &&
         trans.symbol==_Symbol && HistoryDealSelect(trans.deal))
      {
         long entry=HistoryDealGetInteger(trans.deal,DEAL_ENTRY);
         if(entry==DEAL_ENTRY_OUT || entry==DEAL_ENTRY_OUT_BY)
         {
            long owner=ResolveClosedOwnerMagicT178(trans.deal);
            if(HistoryDealSelect(trans.deal))
            {
               long type=HistoryDealGetInteger(trans.deal,DEAL_TYPE);
               eRecoveryCoreDirection dir=recovery_CORE_BUY;
               if(MapCoreClosingDealT178(owner,type,dir))
               {
                  bool strictProof=false;
                  eRecoveryT179RealTpProof proof=ClassifyCoreRealTpDealT179(
                     dir,trans.deal,strictProof);
                  bool recoveryOwns=T179RecoveryOwnsSide(dir);
                  if(proof==RECOVERY_T179_TP_EXTERNAL)
                  {
                     if(strictProof && recoveryOwns)
                     {
                        m_tpPersistenceFault=true;
                        Log_Error("Recovery","LỖI "+Recovery_DirectionName(dir)+
                                  " | Broker TP có strict proof nhưng thiếu durable epoch membership | giữ fail-closed, không gắn nhãn manual/external");
                        return true;
                     }
                     return CRecoveryExitCoordinator::OnTradeTransaction(trans);
                  }
                  double tp=ProgrammedTpFromDealT178(trans.deal);
                  if(!HistoryDealSelect(trans.deal)) return true;
                  ulong positionId=(ulong)HistoryDealGetInteger(trans.deal,DEAL_POSITION_ID);
                  datetime when=(datetime)HistoryDealGetInteger(trans.deal,DEAL_TIME);
                  string persistWhy="";
                  if(!MarkTpEpochSettlingT179(dir,positionId,tp,when,persistWhy))
                  {
                     m_tpPersistenceFault=true;
                     Log_Error("Recovery","LỖI "+Recovery_DirectionName(dir)+
                               " | Không lưu được settlement epoch REAL TP | "+persistWhy);
                     return true;
                  }
                  eRecoveryExitCoordRequest req=CRecoveryExitCoordinator::BeginFullSideClose(
                     dir,recovery_EXIT_REASON_LEGACY_TP,when);
                  bool needsCoordination=req!=recovery_EXIT_BYPASS;
                  if(needsCoordination)
                  {
                     Log_Info("Recovery","TP THẬT "+Recovery_DirectionName(dir)+
                              " | Broker đang chốt durable cohort | Recovery dọn side theo chu kỳ an toàn");
                  }
                  else
                     Log_Info("Recovery","TP THẬT "+Recovery_DirectionName(dir)+
                              " | Strict pre-ownership proof | không phụ thuộc live cohort, không báo lỗi đối soát");
                  MaybeCompleteTpEpoch(dir);
                  // Suppress normal ARCS deal accounting. The side coordinator
                  // consumes live topology; caller still advances deal cursor.
                  return true;
               }
            }
         }
      }
      return CRecoveryExitCoordinator::OnTradeTransaction(trans);
   }
};

// Downstream Strategy/EA declarations resolve to the T17.8 coordinator while
// the complete T17.7 implementation stays available as the direct base class.
#define CRecoveryExitCoordinator CRecoveryExitCoordinatorT178

#endif // BD_RECOVERY_EXIT_COORDINATOR_T178_WRAPPER_MQH
