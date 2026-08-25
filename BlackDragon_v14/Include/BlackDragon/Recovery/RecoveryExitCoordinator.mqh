//+------------------------------------------------------------------+
//| RecoveryExitCoordinator.mqh — T17.8 REAL broker TP wrapper      |
//| Base T17.7/T16 coordinator remains byte-identical in T177Base.   |
//| Expected Core broker TP is never misclassified as manual/external.|
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_EXIT_COORDINATOR_T178_WRAPPER_MQH
#define BD_RECOVERY_EXIT_COORDINATOR_T178_WRAPPER_MQH

#include "RecoveryExitCoordinatorT177Base.mqh"
#include "RecoveryT178RuntimePolicy.mqh"
#include <BlackDragon/Config.mqh>

#define BD_T178_TP_MAGIC   0x38505452 // "RTP8"
#define BD_T178_TP_VERSION 1

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
   double targetTp;
   datetime startedAt;
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

   bool ExpectedCoreRealTpDealT178(const eRecoveryCoreDirection dir,
                                   const ulong deal) const
   {
      if(deal==0 || !HistoryDealSelect(deal)) return false;
      long owner=ResolveClosedOwnerMagicT178(deal);
      if(!HistoryDealSelect(deal)) return false;
      long reason=HistoryDealGetInteger(deal,DEAL_REASON);
      double dealPrice=HistoryDealGetDouble(deal,DEAL_PRICE);
      double programmedTp=ProgrammedTpFromDealT178(deal);
      double tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
      double spread=(double)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD)*_Point;
      if(tick<=0.0) return false;
      double tpTolerance=MathMax(2.0*tick,_Point);
      double fillTolerance=MathMax(500.0*tick,5.0*spread+5.0*tick);
      bool cohort=programmedTp>0.0 && LiveCoreTpCohortMatchesT178(dir,programmedTp,tpTolerance);
      return Recovery_T178ExpectedCoreRealTpPure(TP_Mode==mode_Real,
                                                  Cfg.TP!=0,
                                                  owner==(long)Magic,
                                                  reason==DEAL_REASON_TP,
                                                  programmedTp,
                                                  dealPrice,
                                                  fillTolerance,
                                                  cohort);
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

   bool ArmTpEpoch(const eRecoveryCoreDirection dir,
                   const double targetTp,
                   const datetime now,
                   string &why)
   {
      int idx=T178Index(dir);
      SRecoveryT178TpEpoch old=m_tpEpoch[idx];
      m_tpEpoch[idx].active=1;
      m_tpEpoch[idx].dir=(int)dir;
      m_tpEpoch[idx].targetTp=targetTp;
      if(m_tpEpoch[idx].startedAt<=0) m_tpEpoch[idx].startedAt=now;
      if(SaveTpEpochs(why)) return true;
      m_tpEpoch[idx]=old;
      return false;
   }

   void MaybeCompleteTpEpoch(const eRecoveryCoreDirection dir)
   {
      int idx=T178Index(dir);
      if(m_tpEpoch[idx].active==0) return;
      if(CoreUnitsT178(dir)>0 || RecoveryUnitsT178(dir)>0 || ReconcileHold(dir)) return;
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
      m_tpFile="BD_T178_REALTP_"+(string)AccountInfoInteger(ACCOUNT_LOGIN)+"_"+
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
               if(MapCoreClosingDealT178(owner,type,dir) &&
                  ExpectedCoreRealTpDealT178(dir,trans.deal))
               {
                  double tp=ProgrammedTpFromDealT178(trans.deal);
                  datetime when=(datetime)HistoryDealGetInteger(trans.deal,DEAL_TIME);
                  eRecoveryExitCoordRequest req=CRecoveryExitCoordinator::BeginFullSideClose(
                     dir,recovery_EXIT_REASON_LEGACY_TP,when);
                  bool needsCoordination=req!=recovery_EXIT_BYPASS;
                  eRecoveryT178RealTpDisposition d=
                     Recovery_T178RealTpDispositionPure(true,needsCoordination);
                  if(d==RECOVERY_T178_REAL_TP_COORDINATE_FULL_SIDE)
                  {
                     string persistWhy="";
                     if(!ArmTpEpoch(dir,tp,when,persistWhy))
                     {
                        m_tpPersistenceFault=true;
                        Log_Error("Recovery","LỖI "+Recovery_DirectionName(dir)+
                                  " | Không lưu được chu kỳ REAL TP | "+persistWhy);
                     }
                     else
                        Log_Info("Recovery","TP THẬT "+Recovery_DirectionName(dir)+
                                 " | Broker đang chốt Core | Recovery dọn side theo chu kỳ an toàn");
                  }
                  else
                     Log_Info("Recovery","TP THẬT "+Recovery_DirectionName(dir)+
                              " | Broker chốt Core trước khi Recovery sở hữu side | không báo lỗi đối soát");
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
