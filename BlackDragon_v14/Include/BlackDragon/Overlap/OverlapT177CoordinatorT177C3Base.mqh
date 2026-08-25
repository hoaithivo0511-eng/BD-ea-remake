//+------------------------------------------------------------------+
//| OverlapT177Coordinator.mqh — T17.7 C3 durable Overlap Stage C   |
//| Persist-before-mutate, broker-confirmed leg1, post-fill recheck. |
//+------------------------------------------------------------------+
#ifndef BD_OVERLAP_T177_COORDINATOR_MQH
#define BD_OVERLAP_T177_COORDINATOR_MQH

#include "OverlapT177Policy.mqh"
#include <BlackDragon/ExecutionLayer.mqh>
#include <BlackDragon/EntryFilters.mqh>
#include <BlackDragon/Recovery/RecoveryExitCoordinator.mqh>
#include <BlackDragon/Recovery/RecoveryMutationPolicy.mqh>
#include <BlackDragon/Recovery/RecoveryTypes.mqh>

#define BD_OVERLAP_T177_PERSIST_MAGIC   0x374C564F // "OVL7"
#define BD_OVERLAP_T177_PERSIST_VERSION 1
#define BD_OVERLAP_T177_CYCLE_BASE      17730

struct SOverlapT177PersistHeader
{
   uint magic;
   uint version;
   uint payloadSize;
   uint checksum;
};

struct SOverlapT177PersistIdentity
{
   long     accountLogin;
   uint     symbolHash;
   long     coreMagic;
   datetime savedAt;
   long     saveSequence;
};

struct SOverlapT177Side
{
   int      state;
   int      dir;
   int      route;
   ulong    firstTicket;       // losing leg; closed second
   ulong    lastTicket;        // winning leg; closed first
   ulong    firstPositionId;
   ulong    lastPositionId;
   long     firstOwnerMagic;
   long     lastOwnerMagic;
   double   firstVolume;
   double   lastVolume;
   double   leg1BaselineCash;
   double   leg1BaselineClosedVolume;
   double   leg1RealizedCash;
   datetime armedAt;
   datetime stateAt;
   datetime lastAttemptAt;
};

uint Overlap_T177Fnv1aBytes(const uchar &bytes[])
{
   uint h = 2166136261;
   for(int i = 0; i < ArraySize(bytes); i++)
   {
      h ^= (uint)bytes[i];
      h *= 16777619;
   }
   return h;
}

string Overlap_T177SafeToken(string text)
{
   StringReplace(text, "\\", "_");
   StringReplace(text, "/", "_");
   StringReplace(text, ":", "_");
   StringReplace(text, "*", "_");
   StringReplace(text, "?", "_");
   StringReplace(text, "\"", "_");
   StringReplace(text, "<", "_");
   StringReplace(text, ">", "_");
   StringReplace(text, "|", "_");
   return text;
}

class COverlapT177Coordinator
{
private:
   CExecutionLayer          *m_exec;
   CRecoveryEngine          *m_recovery;
   CRecoveryExitCoordinator *m_recoveryExit;
   SOverlapT177Side          m_side[2];
   bool                      m_loadedFromDisk[2];
   bool                      m_globalReconcile;
   string                    m_file;
   string                    m_temp;
   long                      m_saveSequence;

   int Index(const int dir) const { return dir == BD_DIR_SELL ? 1 : 0; }
   int Direction(const int idx) const { return idx == 1 ? BD_DIR_SELL : BD_DIR_BUY; }
   int CycleKey(const int dir) const { return BD_OVERLAP_T177_CYCLE_BASE + dir; }
   eRecoveryCoreDirection RecoveryDir(const int dir) const
   {
      return dir == BD_DIR_BUY ? recovery_CORE_BUY : recovery_CORE_SELL;
   }

   void ResetSide(const int idx)
   {
      ZeroMemory(m_side[idx]);
      m_side[idx].state = (int)overlap_T177_IDLE;
      m_side[idx].dir = Direction(idx);
      m_side[idx].route = (int)overlap_T177_ROUTE_NONE;
      m_loadedFromDisk[idx] = false;
   }

   bool AnyPersistable() const
   {
      for(int i = 0; i < 2; i++)
      {
         eOverlapT177State s = (eOverlapT177State)m_side[i].state;
         if(Overlap_T177BlocksSidePure(s)) return true;
      }
      return false;
   }

   uint PayloadSize() const
   {
      return (uint)(sizeof(SOverlapT177PersistIdentity) +
                    2 * sizeof(SOverlapT177Side));
   }

   bool ReadPayloadRaw(const int handle, uchar &raw[], string &why) const
   {
      uint size = PayloadSize();
      ArrayResize(raw, (int)size);
      if(!FileSeek(handle, (long)sizeof(SOverlapT177PersistHeader), SEEK_SET))
      { why = "không seek được payload Overlap"; return false; }
      uint n = FileReadArray(handle, raw, 0, (int)size);
      if(n != size)
      { why = "payload Overlap thiếu byte"; return false; }
      return true;
   }

   bool SaveAll(string &why)
   {
      why = "";
      if(MQLInfoInteger(MQL_TESTER) && !RecoveryTesterResumeState_) return true;
      if(m_globalReconcile) { why = "state Overlap đang ở chế độ đối soát"; return false; }
      if(m_file == "") { why = "persistence Overlap chưa khởi tạo"; return false; }

      if(!AnyPersistable())
      {
         FileDelete(m_temp);
         FileDelete(m_file);
         return true;
      }

      SOverlapT177PersistHeader header;
      header.magic = BD_OVERLAP_T177_PERSIST_MAGIC;
      header.version = BD_OVERLAP_T177_PERSIST_VERSION;
      header.payloadSize = PayloadSize();
      header.checksum = 0;

      SOverlapT177PersistIdentity identity;
      ZeroMemory(identity);
      identity.accountLogin = AccountInfoInteger(ACCOUNT_LOGIN);
      identity.symbolHash = Recovery_Fnv1aTextPure(_Symbol);
      identity.coreMagic = (long)Magic;
      identity.savedAt = TimeCurrent();
      identity.saveSequence = ++m_saveSequence;

      FileDelete(m_temp);
      int h = FileOpen(m_temp, FILE_WRITE|FILE_BIN);
      if(h == INVALID_HANDLE) { why = "không tạo được temp Overlap"; return false; }
      bool ok = FileWriteStruct(h, header) == sizeof(SOverlapT177PersistHeader) &&
                FileWriteStruct(h, identity) == sizeof(SOverlapT177PersistIdentity) &&
                FileWriteStruct(h, m_side[0]) == sizeof(SOverlapT177Side) &&
                FileWriteStruct(h, m_side[1]) == sizeof(SOverlapT177Side);
      FileFlush(h);
      FileClose(h);
      if(!ok) { FileDelete(m_temp); why = "ghi state Overlap thiếu byte"; return false; }

      h = FileOpen(m_temp, FILE_READ|FILE_BIN);
      if(h == INVALID_HANDLE) { FileDelete(m_temp); why = "không mở lại temp Overlap"; return false; }
      uchar raw[];
      if(!ReadPayloadRaw(h, raw, why))
      { FileClose(h); FileDelete(m_temp); return false; }
      FileClose(h);
      header.checksum = Overlap_T177Fnv1aBytes(raw);

      h = FileOpen(m_temp, FILE_READ|FILE_WRITE|FILE_BIN);
      if(h == INVALID_HANDLE) { FileDelete(m_temp); why = "không finalize được temp Overlap"; return false; }
      if(!FileSeek(h, 0, SEEK_SET) ||
         FileWriteStruct(h, header) != sizeof(SOverlapT177PersistHeader))
      {
         FileClose(h); FileDelete(m_temp); why = "không finalize được header Overlap"; return false;
      }
      FileFlush(h);
      ulong finalSize = FileSize(h);
      FileClose(h);
      ulong expected = (ulong)sizeof(SOverlapT177PersistHeader) + (ulong)PayloadSize();
      if(finalSize != expected)
      { FileDelete(m_temp); why = "kích thước state Overlap không khớp"; return false; }
      if(!FileMove(m_temp, 0, m_file, FILE_REWRITE))
      { FileDelete(m_temp); why = "atomic replace state Overlap thất bại"; return false; }
      return true;
   }

   bool LoadAll(string &why)
   {
      why = "";
      if(!Recovery_ShouldReusePersistedStatePure((bool)MQLInfoInteger(MQL_TESTER),
                                                 RecoveryTesterResumeState_))
         return true;
      if(!FileIsExist(m_file)) return true;
      int h = FileOpen(m_file, FILE_READ|FILE_BIN);
      if(h == INVALID_HANDLE) { why = "không mở được state Overlap"; return false; }

      ulong expected = (ulong)sizeof(SOverlapT177PersistHeader) + (ulong)PayloadSize();
      if(FileSize(h) != expected)
      { FileClose(h); why = "kích thước state Overlap sai schema"; return false; }

      SOverlapT177PersistHeader header;
      if(FileReadStruct(h, header) != sizeof(SOverlapT177PersistHeader) ||
         header.magic != BD_OVERLAP_T177_PERSIST_MAGIC ||
         header.version != BD_OVERLAP_T177_PERSIST_VERSION ||
         header.payloadSize != PayloadSize())
      { FileClose(h); why = "header/version state Overlap không hợp lệ"; return false; }

      uchar raw[];
      if(!ReadPayloadRaw(h, raw, why)) { FileClose(h); return false; }
      if(Overlap_T177Fnv1aBytes(raw) != header.checksum)
      { FileClose(h); why = "checksum state Overlap không khớp"; return false; }
      if(!FileSeek(h, (long)sizeof(SOverlapT177PersistHeader), SEEK_SET))
      { FileClose(h); why = "không seek được state Overlap"; return false; }

      SOverlapT177PersistIdentity identity;
      SOverlapT177Side side0, side1;
      if(FileReadStruct(h, identity) != sizeof(SOverlapT177PersistIdentity) ||
         FileReadStruct(h, side0) != sizeof(SOverlapT177Side) ||
         FileReadStruct(h, side1) != sizeof(SOverlapT177Side))
      { FileClose(h); why = "decode state Overlap thất bại"; return false; }
      FileClose(h);

      if(identity.accountLogin != AccountInfoInteger(ACCOUNT_LOGIN) ||
         identity.symbolHash != Recovery_Fnv1aTextPure(_Symbol) ||
         identity.coreMagic != (long)Magic)
      { why = "identity state Overlap không khớp runtime"; return false; }
      if(!Overlap_T177StateValidPure(side0.state) ||
         !Overlap_T177StateValidPure(side1.state) ||
         side0.dir != BD_DIR_BUY || side1.dir != BD_DIR_SELL)
      { why = "state/side Overlap không hợp lệ"; return false; }

      m_side[0] = side0;
      m_side[1] = side1;
      m_saveSequence = identity.saveSequence;
      for(int i = 0; i < 2; i++)
      {
         if((eOverlapT177State)m_side[i].state == overlap_T177_COMPLETE)
            ResetSide(i);
         else if(Overlap_T177BlocksSidePure((eOverlapT177State)m_side[i].state))
            m_loadedFromDisk[i] = true;
      }
      return true;
   }

   void LatchReconcile(const int idx, const string why)
   {
      m_side[idx].state = (int)overlap_T177_RECONCILE;
      m_side[idx].stateAt = TimeCurrent();
      string persistWhy = "";
      SaveAll(persistWhy);
      Log_Warn("Overlap", "t177reconcile" + (string)idx,
               "LỖI " + (idx == 0 ? "BUY" : "SELL") +
               " | Không xác định an toàn trạng thái Overlap | " + why);
   }

   bool SetState(const int idx, const eOverlapT177State state,
                 const datetime now, string &why)
   {
      why = "";
      SOverlapT177Side old = m_side[idx];
      m_side[idx].state = (int)state;
      m_side[idx].stateAt = now;
      if(SaveAll(why)) return true;
      m_side[idx] = old;
      return false;
   }

   bool ReadExitTotals(const ulong positionId,
                       double &cash,
                       double &closedVolume) const
   {
      cash = 0.0;
      closedVolume = 0.0;
      if(positionId == 0 || !HistorySelectByPosition(positionId)) return false;
      for(int i = 0; i < HistoryDealsTotal(); i++)
      {
         ulong deal = HistoryDealGetTicket(i);
         if(deal == 0 ||
            (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID) != positionId)
            continue;
         long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
         if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY &&
            entry != DEAL_ENTRY_INOUT)
            continue;
         closedVolume += HistoryDealGetDouble(deal, DEAL_VOLUME);
         cash += HistoryDealGetDouble(deal, DEAL_PROFIT)
               + HistoryDealGetDouble(deal, DEAL_SWAP)
               + HistoryDealGetDouble(deal, DEAL_COMMISSION)
               + HistoryDealGetDouble(deal, DEAL_FEE);
      }
      return true;
   }

   bool ReadLiveTicket(const ulong ticket, const int dir,
                       const long expectedMagic, const ulong expectedPositionId,
                       bool &exists, double &volume, double &floating) const
   {
      exists = false; volume = 0.0; floating = 0.0;
      if(ticket == 0 || !PositionSelectByTicket(ticket)) return true;
      exists = true;
      long wanted = dir == BD_DIR_BUY ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol ||
         PositionGetInteger(POSITION_TYPE) != wanted ||
         PositionGetInteger(POSITION_MAGIC) != expectedMagic ||
         (ulong)PositionGetInteger(POSITION_IDENTIFIER) != expectedPositionId)
         return false;
      volume = PositionGetDouble(POSITION_VOLUME);
      floating = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      return volume > 0.0;
   }

   bool CaptureTicket(const ulong ticket, const int dir,
                      long &ownerMagic, ulong &positionId,
                      double &volume, double &floating) const
   {
      if(ticket == 0 || !PositionSelectByTicket(ticket)) return false;
      long wanted = dir == BD_DIR_BUY ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol ||
         PositionGetInteger(POSITION_TYPE) != wanted)
         return false;
      ownerMagic = PositionGetInteger(POSITION_MAGIC);
      if(!Basket_OwnsMagic(ownerMagic, (long)Magic, flag_Hand_Ord)) return false;
      positionId = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
      volume = PositionGetDouble(POSITION_VOLUME);
      floating = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      return positionId != 0 && volume > 0.0;
   }

   double ExecutionReserveCash(const EAContext &ctx,
                               const double totalLots,
                               const int requests) const
   {
      double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double spreadPrice = MathMax(ctx.ask - ctx.bid, 0.0);
      double deviationPrice = Cfg.SlippagePrice;
      return Exit_OverlapExecutionReserveCashPure(spreadPrice, deviationPrice,
                                                  totalLots, requests,
                                                  tickSize, tickValue);
   }

   eOverlapT177Route RouteForSide(const int dir, bool &defer) const
   {
      defer = false;
      if(RecoveryMode_ != recovery_ACTIVE || m_recovery == NULL ||
         m_recoveryExit == NULL)
         return overlap_T177_ROUTE_DIRECT;
      SRecoveryCycle cycle;
      m_recovery.GetCycle(RecoveryDir(dir), cycle);
      eRecoveryOverlapPolicy p = Recovery_OverlapPolicyPure(cycle.state);
      if(p == recovery_OVERLAP_BYPASS) return overlap_T177_ROUTE_DIRECT;
      if(p == recovery_OVERLAP_DEFER || !m_recovery.ActiveReady())
      { defer = true; return overlap_T177_ROUTE_NONE; }
      return overlap_T177_ROUTE_RECOVERY;
   }

   eOverlapT177DriveDisposition SubmitLeg(const int idx, const bool leg1,
                                          const EAContext &ctx)
   {
      int dir = Direction(idx);
      ulong ticket = leg1 ? m_side[idx].lastTicket : m_side[idx].firstTicket;
      long owner = leg1 ? m_side[idx].lastOwnerMagic : m_side[idx].firstOwnerMagic;
      ulong positionId = leg1 ? m_side[idx].lastPositionId : m_side[idx].firstPositionId;
      bool exists = false;
      double volume = 0.0, floating = 0.0;
      if(!ReadLiveTicket(ticket, dir, owner, positionId, exists, volume, floating))
      { LatchReconcile(idx, "ticket đổi owner/identity trước khi gửi close"); return overlap_T177_DRIVE_RECONCILE; }
      if(!exists)
      {
         string sw = "";
         if(!SetState(idx, leg1 ? overlap_T177_LEG1_CONFIRMED : overlap_T177_COMPLETE,
                      ctx.now, sw))
         { LatchReconcile(idx, "không lưu được trạng thái ticket đã đóng"); return overlap_T177_DRIVE_RECONCILE; }
         return overlap_T177_DRIVE_WAIT;
      }

      if(m_side[idx].lastAttemptAt > 0 && ctx.now <= m_side[idx].lastAttemptAt)
         return overlap_T177_DRIVE_WAIT;

      bool defer = false;
      eOverlapT177Route route = RouteForSide(dir, defer);
      if(defer) return overlap_T177_DRIVE_WAIT;

      SOverlapT177Side old = m_side[idx];
      m_side[idx].state = (int)(leg1 ? overlap_T177_LEG1_SUBMITTED : overlap_T177_LEG2_SUBMITTED);
      m_side[idx].stateAt = ctx.now;
      m_side[idx].lastAttemptAt = ctx.now;
      m_side[idx].route = (int)route;
      m_loadedFromDisk[idx] = false;
      string persistWhy = "";
      if(!SaveAll(persistWhy))
      {
         m_side[idx] = old;
         Log_WarnEvery("Overlap", "t177persist" + (string)idx,
                       "CHỜ " + (idx == 0 ? "BUY" : "SELL") +
                       " | Chưa lưu được nghĩa vụ cặp trước khi đóng | " + persistWhy,
                       Recovery_T165WaitLogSecondsPure(RecoveryWaitLogSeconds_));
         return overlap_T177_DRIVE_WAIT;
      }

      if(route == overlap_T177_ROUTE_RECOVERY)
      {
         eRecoveryExitCoordRequest cr = m_recoveryExit.BeginTicketClose(
            RecoveryDir(dir), ticket, 0,
            recovery_EXIT_REASON_LEGACY_OVERLAP, ctx.now);
         if(cr == recovery_EXIT_BLOCKED)
         {
            m_side[idx] = old;
            if(!SaveAll(persistWhy))
            { LatchReconcile(idx, "không khôi phục được state sau khi Recovery chặn leg"); return overlap_T177_DRIVE_RECONCILE; }
            return overlap_T177_DRIVE_WAIT;
         }
         if(cr == recovery_EXIT_BYPASS)
         {
            m_side[idx].route = (int)overlap_T177_ROUTE_DIRECT;
            if(!SaveAll(persistWhy))
            { LatchReconcile(idx, "không lưu được chuyển route DIRECT trước close"); return overlap_T177_DRIVE_RECONCILE; }
            route = overlap_T177_ROUTE_DIRECT;
         }
         else
         {
            string recoveryWhy = "";
            m_recoveryExit.Drive(ctx.now, recoveryWhy);
            if(recoveryWhy != "")
               Log_WarnEvery("Overlap", "t177recovery" + (string)idx,
                             recoveryWhy,
                             Recovery_T165WaitLogSecondsPure(RecoveryWaitLogSeconds_));
            return overlap_T177_DRIVE_PENDING;
         }
      }

      bool sent = m_exec.ClosePositionVolumeOwned(ticket, volume, owner,
                                                   CycleKey(dir),
                                                   EXEC_CMD_CORE_PYRAMID_CLOSE,
                                                   EXEC_RECONCILE_FAIL_CLOSED);
      if(sent) return overlap_T177_DRIVE_MUTATED;
      m_exec.ReconcileCycle(CycleKey(dir));
      if(m_exec.HasReconcileRequired(CycleKey(dir)))
      { LatchReconcile(idx, "kết quả gửi close trực tiếp mơ hồ"); return overlap_T177_DRIVE_RECONCILE; }

      // Proven explicit rejection/non-execution: no blind same-request retry.
      m_side[idx] = old;
      if(!SaveAll(persistWhy))
      { LatchReconcile(idx, "không khôi phục được state sau close bị từ chối"); return overlap_T177_DRIVE_RECONCILE; }
      return overlap_T177_DRIVE_WAIT;
   }

   eOverlapT177DriveDisposition ObserveSubmitted(const int idx,
                                                 const bool leg1,
                                                 const EAContext &ctx)
   {
      int dir = Direction(idx);
      ulong ticket = leg1 ? m_side[idx].lastTicket : m_side[idx].firstTicket;
      long owner = leg1 ? m_side[idx].lastOwnerMagic : m_side[idx].firstOwnerMagic;
      ulong positionId = leg1 ? m_side[idx].lastPositionId : m_side[idx].firstPositionId;
      bool exists = false;
      double volume = 0.0, floating = 0.0;
      if(!ReadLiveTicket(ticket, dir, owner, positionId, exists, volume, floating))
      { LatchReconcile(idx, "ticket đổi owner/identity khi đang chờ broker"); return overlap_T177_DRIVE_RECONCILE; }

      eOverlapT177Route route = (eOverlapT177Route)m_side[idx].route;
      if(route == overlap_T177_ROUTE_RECOVERY)
      {
         if(m_loadedFromDisk[idx] && exists)
         { LatchReconcile(idx, "restart giữa request Recovery; ticket vẫn còn nên outcome mơ hồ"); return overlap_T177_DRIVE_RECONCILE; }
         if(m_recoveryExit == NULL)
         { LatchReconcile(idx, "mất Recovery Exit Coordinator khi leg đang submitted"); return overlap_T177_DRIVE_RECONCILE; }
         if(m_recoveryExit.ReconcileHold(RecoveryDir(dir)))
         { LatchReconcile(idx, "Recovery Exit Coordinator yêu cầu đối soát"); return overlap_T177_DRIVE_RECONCILE; }
         if(m_recoveryExit.HasBlockingWork())
         {
            string why = "";
            m_recoveryExit.Drive(ctx.now, why);
            if(m_recoveryExit.ReconcileHold(RecoveryDir(dir)))
            { LatchReconcile(idx, "Recovery close chuyển sang đối soát: " + why); return overlap_T177_DRIVE_RECONCILE; }
            return overlap_T177_DRIVE_PENDING;
         }
         if(exists)
         { LatchReconcile(idx, "Recovery coordinator đã rảnh nhưng ticket leg vẫn còn"); return overlap_T177_DRIVE_RECONCILE; }
      }
      else if(route == overlap_T177_ROUTE_DIRECT)
      {
         m_exec.ReconcileCycle(CycleKey(dir));
         bool pending = m_exec.HasPendingForCycle(CycleKey(dir));
         bool reconcile = m_exec.HasReconcileRequired(CycleKey(dir));
         eOverlapT177SubmitObservation obs = Overlap_T177SubmittedObservationPure(
            m_loadedFromDisk[idx], exists, pending, reconcile);
         if(obs == overlap_T177_OBS_RECONCILE)
         { LatchReconcile(idx, "journal close trực tiếp yêu cầu đối soát"); return overlap_T177_DRIVE_RECONCILE; }
         if(obs == overlap_T177_OBS_PENDING) return overlap_T177_DRIVE_PENDING;
         if(obs == overlap_T177_OBS_REJECTED)
         {
            string why = "";
            if(!SetState(idx, leg1 ? overlap_T177_PAIR_ARMED : overlap_T177_LEG2_WAIT_SAFE,
                         ctx.now, why))
            { LatchReconcile(idx, "không lưu được trạng thái sau request bị từ chối"); return overlap_T177_DRIVE_RECONCILE; }
            m_side[idx].route = (int)overlap_T177_ROUTE_NONE;
            m_loadedFromDisk[idx] = false;
            SaveAll(why);
            return overlap_T177_DRIVE_WAIT;
         }
      }
      else
      { LatchReconcile(idx, "submitted state thiếu route thực thi"); return overlap_T177_DRIVE_RECONCILE; }

      string stateWhy = "";
      if(!SetState(idx, leg1 ? overlap_T177_LEG1_CONFIRMED : overlap_T177_COMPLETE,
                   ctx.now, stateWhy))
      { LatchReconcile(idx, "không lưu được broker-confirmed leg"); return overlap_T177_DRIVE_RECONCILE; }
      m_loadedFromDisk[idx] = false;
      return overlap_T177_DRIVE_WAIT;
   }

   eOverlapT177DriveDisposition DriveArmed(const int idx,
                                          const EAContext &ctx,
                                          const BasketSide &side)
   {
      SOverlapT177Side s = m_side[idx];
      bool firstExists = false, lastExists = false;
      double firstVolume = 0.0, lastVolume = 0.0;
      double firstFloating = 0.0, lastFloating = 0.0;
      if(!ReadLiveTicket(s.firstTicket, s.dir, s.firstOwnerMagic, s.firstPositionId,
                         firstExists, firstVolume, firstFloating) ||
         !ReadLiveTicket(s.lastTicket, s.dir, s.lastOwnerMagic, s.lastPositionId,
                         lastExists, lastVolume, lastFloating))
      { LatchReconcile(idx, "pair identity đổi trước leg 1"); return overlap_T177_DRIVE_RECONCILE; }
      if(!firstExists || !lastExists)
      {
         // No Overlap-owned mutation has happened yet; stale pair can be safely
         // dropped and a later ExitPolicy evaluation may arm a fresh pair.
         ResetSide(idx);
         string why = ""; SaveAll(why);
         return overlap_T177_DRIVE_WAIT;
      }
      double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      double eps = step > 0.0 ? step * 0.5 : 1e-9;
      if(MathAbs(firstVolume - s.firstVolume) > eps ||
         MathAbs(lastVolume - s.lastVolume) > eps)
      {
         ResetSide(idx);
         string why = ""; SaveAll(why);
         return overlap_T177_DRIVE_WAIT;
      }

      double reserve = ExecutionReserveCash(ctx, firstVolume + lastVolume, 2);
      if(!Overlap_T177PreLeg1EligiblePure(side.count, OverlapOrderNumber, Overlap,
                                          firstFloating, lastFloating,
                                          OverlapPercent, reserve))
      {
         ResetSide(idx);
         string why = ""; SaveAll(why);
         return overlap_T177_DRIVE_WAIT;
      }
      return SubmitLeg(idx, true, ctx);
   }

   eOverlapT177DriveDisposition ReadLeg1Realized(const int idx,
                                                 const EAContext &ctx)
   {
      double cash = 0.0, closed = 0.0;
      bool ok = ReadExitTotals(m_side[idx].lastPositionId, cash, closed);
      double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      double eps = step > 0.0 ? step * 0.5 : 1e-9;
      double deltaClosed = closed - m_side[idx].leg1BaselineClosedVolume;
      if(!ok || deltaClosed + eps < m_side[idx].lastVolume)
      {
         if(ctx.now > m_side[idx].stateAt + BD_ASYNC_CLOSE_HARD_TIMEOUT_SEC)
         { LatchReconcile(idx, "ticket leg1 đã mất nhưng history chưa chứng minh đủ khối lượng close"); return overlap_T177_DRIVE_RECONCILE; }
         return overlap_T177_DRIVE_WAIT;
      }
      m_side[idx].leg1RealizedCash = cash - m_side[idx].leg1BaselineCash;
      string why = "";
      if(!SetState(idx, overlap_T177_LEG2_RECHECK, ctx.now, why))
      { LatchReconcile(idx, "không lưu được realized leg1"); return overlap_T177_DRIVE_RECONCILE; }
      return overlap_T177_DRIVE_WAIT;
   }

   eOverlapT177DriveDisposition RecheckLeg2(const int idx,
                                            const EAContext &ctx)
   {
      SOverlapT177Side s = m_side[idx];
      bool exists = false;
      double volume = 0.0, floating = 0.0;
      if(!ReadLiveTicket(s.firstTicket, s.dir, s.firstOwnerMagic, s.firstPositionId,
                         exists, volume, floating))
      { LatchReconcile(idx, "leg2 đổi owner/identity sau khi leg1 đóng"); return overlap_T177_DRIVE_RECONCILE; }
      if(!exists)
      {
         string why = "";
         if(!SetState(idx, overlap_T177_COMPLETE, ctx.now, why))
         { LatchReconcile(idx, "không lưu được COMPLETE khi leg2 đã đóng"); return overlap_T177_DRIVE_RECONCILE; }
         return overlap_T177_DRIVE_WAIT;
      }

      double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      double eps = step > 0.0 ? step * 0.5 : 1e-9;
      if(volume > s.firstVolume + eps)
      { LatchReconcile(idx, "khối lượng leg2 tăng ngoài nghĩa vụ đã khóa"); return overlap_T177_DRIVE_RECONCILE; }
      if(volume + eps < s.firstVolume)
      {
         // Risk-reducing partial shrink from another managed subsystem is safe;
         // the remaining obligation shrinks and is persisted before recheck.
         m_side[idx].firstVolume = volume;
         s.firstVolume = volume;
         string shrinkWhy = "";
         if(!SaveAll(shrinkWhy))
         { LatchReconcile(idx, "không lưu được khối lượng leg2 sau partial close"); return overlap_T177_DRIVE_RECONCILE; }
      }

      double reserve = ExecutionReserveCash(ctx, volume, 1);
      if(!Overlap_T177Leg2SafePure(s.leg1RealizedCash, floating, reserve))
      {
         if((eOverlapT177State)s.state != overlap_T177_LEG2_WAIT_SAFE)
         {
            string why = "";
            if(!SetState(idx, overlap_T177_LEG2_WAIT_SAFE, ctx.now, why))
            { LatchReconcile(idx, "không lưu được durable WAIT leg2"); return overlap_T177_DRIVE_RECONCILE; }
         }
         double projected = s.leg1RealizedCash + floating -
                            (reserve == DBL_MAX ? 0.0 : reserve);
         Log_WarnEvery("Overlap", "t177leg2wait" + (string)idx,
                       "CHỜ " + (idx == 0 ? "BUY" : "SELL") +
                       " | Lệnh 1 đã đóng, lệnh 2 chưa an toàn | dự kiến=" +
                       (reserve == DBL_MAX ? "N/A" : DoubleToString(projected, 2)) + " USD",
                       Recovery_T165WaitLogSecondsPure(RecoveryWaitLogSeconds_));
         return overlap_T177_DRIVE_WAIT;
      }
      return SubmitLeg(idx, false, ctx);
   }

   void CompleteSide(const int idx)
   {
      Log_Info("Overlap", "HOÀN TẤT " + (idx == 0 ? "BUY" : "SELL") +
               " | Cặp Overlap đã xử lý xong | leg1 realized=" +
               DoubleToString(m_side[idx].leg1RealizedCash, 2) + " USD");
      ResetSide(idx);
      string why = "";
      if(!SaveAll(why) && why != "")
         Log_Warn("Overlap", "t177cleanup" + (string)idx,
                  "không xóa/finalize được state Overlap: " + why);
   }

public:
   COverlapT177Coordinator(void)
   {
      m_exec = NULL;
      m_recovery = NULL;
      m_recoveryExit = NULL;
      m_globalReconcile = false;
      m_file = "";
      m_temp = "";
      m_saveSequence = 0;
      ResetSide(0);
      ResetSide(1);
   }

   bool Init(CExecutionLayer *exec,
             CRecoveryEngine *recovery,
             CRecoveryExitCoordinator *recoveryExit,
             string &why)
   {
      why = "";
      m_exec = exec;
      m_recovery = recovery;
      m_recoveryExit = recoveryExit;
      m_globalReconcile = false;
      m_saveSequence = 0;
      ResetSide(0);
      ResetSide(1);
      if(m_exec == NULL) { why = "ExecutionLayer cho Overlap không khả dụng"; return false; }
      string token = Overlap_T177SafeToken(_Symbol);
      m_file = "BlackDragon_Overlap_T177_" + token + "_" +
               (string)AccountInfoInteger(ACCOUNT_LOGIN) + "_" +
               (string)Magic + ".bin";
      m_temp = m_file + ".tmp";
      if(!LoadAll(why))
      {
         m_globalReconcile = true;
         Log_Warn("Overlap", "t177load",
                  "LỖI HAI PHÍA | State Overlap không đọc được an toàn | " + why);
         return true; // init succeeds but Strategy is fail-closed by Drive().
      }
      return true;
   }

   bool Arm(const int dir, const ulong firstTicket, const ulong lastTicket,
            const datetime now, string &why)
   {
      why = "";
      if(m_globalReconcile) { why = "Overlap đang yêu cầu đối soát"; return false; }
      int idx = Index(dir);
      if(Overlap_T177BlocksSidePure((eOverlapT177State)m_side[idx].state))
      { why = "side đã có nghĩa vụ Overlap"; return false; }
      if(firstTicket == 0 || lastTicket == 0 || firstTicket == lastTicket)
      { why = "cặp ticket Overlap không hợp lệ"; return false; }

      SOverlapT177Side candidate;
      ZeroMemory(candidate);
      candidate.state = (int)overlap_T177_PAIR_ARMED;
      candidate.dir = dir;
      candidate.route = (int)overlap_T177_ROUTE_NONE;
      candidate.firstTicket = firstTicket;
      candidate.lastTicket = lastTicket;
      double firstFloating = 0.0, lastFloating = 0.0;
      if(!CaptureTicket(firstTicket, dir, candidate.firstOwnerMagic,
                        candidate.firstPositionId, candidate.firstVolume,
                        firstFloating) ||
         !CaptureTicket(lastTicket, dir, candidate.lastOwnerMagic,
                        candidate.lastPositionId, candidate.lastVolume,
                        lastFloating))
      { why = "không khóa được exact identity của cặp Overlap"; return false; }
      if(!ReadExitTotals(candidate.lastPositionId,
                         candidate.leg1BaselineCash,
                         candidate.leg1BaselineClosedVolume))
      { why = "không đọc được baseline history của leg1"; return false; }
      candidate.leg1RealizedCash = 0.0;
      candidate.armedAt = now;
      candidate.stateAt = now;
      candidate.lastAttemptAt = 0;

      SOverlapT177Side old = m_side[idx];
      m_side[idx] = candidate;
      m_loadedFromDisk[idx] = false;
      if(!SaveAll(why))
      {
         m_side[idx] = old;
         return false;
      }
      Log_Info("Overlap", "ĐÃ KHÓA CẶP " + (idx == 0 ? "BUY" : "SELL") +
               " | leg1=" + (string)lastTicket + " leg2=" + (string)firstTicket);
      return true;
   }

   bool Active(const int dir) const
   {
      if(m_globalReconcile) return true;
      return Overlap_T177BlocksSidePure((eOverlapT177State)m_side[Index(dir)].state);
   }

   bool BlocksSide(const int dir) const { return Active(dir); }

   bool HasUrgentWork() const
   {
      if(m_globalReconcile) return true;
      for(int i = 0; i < 2; i++)
      {
         eOverlapT177State s = (eOverlapT177State)m_side[i].state;
         if(Overlap_T177SubmittedStatePure(s) || s == overlap_T177_RECONCILE)
            return true;
      }
      return false;
   }

   eOverlapT177DriveDisposition DriveSide(const EAContext &ctx,
                                          const BasketSide &side,
                                          const int dir)
   {
      int idx = Index(dir);
      if(m_globalReconcile) return overlap_T177_DRIVE_RECONCILE;
      eOverlapT177State state = (eOverlapT177State)m_side[idx].state;
      if(state == overlap_T177_IDLE) return overlap_T177_DRIVE_NO_EFFECT;
      if(state == overlap_T177_RECONCILE) return overlap_T177_DRIVE_RECONCILE;

      if(state == overlap_T177_PAIR_ARMED)
         return DriveArmed(idx, ctx, side);
      if(state == overlap_T177_LEG1_SUBMITTED)
         return ObserveSubmitted(idx, true, ctx);
      if(state == overlap_T177_LEG1_CONFIRMED)
         return ReadLeg1Realized(idx, ctx);
      if(state == overlap_T177_LEG2_RECHECK || state == overlap_T177_LEG2_WAIT_SAFE)
         return RecheckLeg2(idx, ctx);
      if(state == overlap_T177_LEG2_SUBMITTED)
         return ObserveSubmitted(idx, false, ctx);
      if(state == overlap_T177_COMPLETE)
      {
         CompleteSide(idx);
         return overlap_T177_DRIVE_WAIT;
      }
      LatchReconcile(idx, "state machine Overlap đi vào trạng thái không hợp lệ");
      return overlap_T177_DRIVE_RECONCILE;
   }

   eOverlapT177DriveDisposition Drive(const EAContext &ctx,
                                      const BasketSide &buy,
                                      const BasketSide &sell)
   {
      if(m_globalReconcile) return overlap_T177_DRIVE_RECONCILE;
      eOverlapT177DriveDisposition b = DriveSide(ctx, buy, BD_DIR_BUY);
      if(Overlap_T177ConsumesStrategyTickPure(b)) return b;
      eOverlapT177DriveDisposition s = DriveSide(ctx, sell, BD_DIR_SELL);
      if(Overlap_T177ConsumesStrategyTickPure(s)) return s;
      if(b == overlap_T177_DRIVE_WAIT || s == overlap_T177_DRIVE_WAIT)
         return overlap_T177_DRIVE_WAIT;
      return overlap_T177_DRIVE_NO_EFFECT;
   }

   void Flush()
   {
      string why = "";
      if(!SaveAll(why) && why != "")
         Log_Warn("Overlap", "t177flush", "không flush được state Overlap: " + why);
   }
};

#endif // BD_OVERLAP_T177_COORDINATOR_MQH
