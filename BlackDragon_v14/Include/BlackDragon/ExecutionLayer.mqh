//+------------------------------------------------------------------+
//| ExecutionLayer.mqh — BlackDragon v14.0.0                         |
//| Purpose   : The ONLY place that calls OrderSend/OrderSendAsync.  |
//|             Sync + Async modes, retry with price refresh,        |
//|             pending-request journal, watchdog (Nhom B).          |
//| Invariants: Engines never call trade functions directly.         |
//|             No Sleep(). Every retcode is checked (fix #1).       |
//| Fixes     : #1 retcode checked on close, #6 price refreshed per  |
//|             retry + per-direction busy flags, #7 no Alert+Sleep, |
//|             AU-14-02 HasPendingModify guards async SL/TP spam,   |
//|             BD-R2 deviation scaled by PointScale (v14.7.2),      |
//|             BD-R1 CLOSE/MODIFY unlock 10s, OPEN keeps 30s,       |
//|             Recovery T2 owner-aware journal + strict reconcile.  |
//| Depends on: Types.mqh, GridEngine.mqh, Logger.mqh, License.mqh   |
//+------------------------------------------------------------------+
#ifndef BD_EXECUTIONLAYER_MQH
#define BD_EXECUTIONLAYER_MQH
#include "Types.mqh"
#include "GridEngine.mqh"
#include "Logger.mqh"
#include "License.mqh"

//--- FE-203: order comment carries the DCA order index: "comment|n"
string Exec_BuildComment(const string baseComment, const int dcaIndex)
{
   if(dcaIndex <= 0) return baseComment;
   return baseComment + "|" + IntegerToString(dcaIndex);
}

//--- BD-002: REQUEST acceptance alone is never completion.
bool Exec_PendingReady(const ePendingEvidence evidence)
{
   return evidence == PENDING_EVIDENCE_RESULT_STATE;
}

//--- BD-R2: scale point-based slippage into broker points.
ulong Exec_Deviation(const int slippagePoints, const int pointScale)
{
   int s = slippagePoints < 0 ? 0 : slippagePoints;
   int k = pointScale < 1 ? 1 : pointScale;
   return (ulong)(s * k);
}

//--- BD-R1: legacy per-intent hard timeout remains unchanged.
int Exec_HardTimeoutSec(const eIntent action)
{
   if(action == INTENT_OPEN_BUY || action == INTENT_OPEN_SELL)
      return BD_ASYNC_HARD_TIMEOUT_SEC;
   return BD_ASYNC_CLOSE_HARD_TIMEOUT_SEC;
}

bool Exec_CloseVolumeResolved(const double beforeVolume, const double currentVolume,
                              const double targetVolume, const double volumeStep)
{
   if(targetVolume <= 0) return false;
   double eps = volumeStep > 0 ? volumeStep * 0.5 : 1e-9;
   return beforeVolume - currentVolume + eps >= targetVolume;
}

//--- BD-R10: preserve the selected position's owner on a close request.
ulong Exec_CloseRequestMagic(const long positionMagic)
{
   return positionMagic > 0 ? (ulong)positionMagic : 0;
}

//--- Recovery T2 pure execution helpers ------------------------------------
void Exec_InitMeta(SExecRequestMeta &meta,
                   const long ownerMagic,
                   const int cycleKey,
                   const eExecCommandType commandType,
                   const eExecReconcilePolicy reconcilePolicy)
{
   meta.ownerMagic      = ownerMagic;
   meta.cycleKey        = cycleKey;
   meta.commandType     = commandType;
   meta.reconcilePolicy = reconcilePolicy;
}

bool Exec_OwnerMatches(const long observedMagic, const long ownerMagic)
{
   return observedMagic == ownerMagic;
}

bool Exec_IsFailClosed(const eExecReconcilePolicy policy)
{
   return policy == EXEC_RECONCILE_FAIL_CLOSED;
}

bool Exec_RetryableRetcode(const uint rc)
{
   return rc == TRADE_RETCODE_REQUOTE || rc == TRADE_RETCODE_PRICE_CHANGED ||
          rc == TRADE_RETCODE_PRICE_OFF || rc == TRADE_RETCODE_TIMEOUT ||
          rc == TRADE_RETCODE_CONNECTION;
}

bool Exec_AmbiguousRetcode(const uint rc)
{
   return rc == TRADE_RETCODE_TIMEOUT || rc == TRADE_RETCODE_CONNECTION;
}

// Strict Recovery commands never blindly retry a timeout/connection outcome:
// the broker may already have accepted the request. Price-only failures remain
// retryable because they are explicit non-execution outcomes.
bool Exec_RetryAllowed(const eExecReconcilePolicy policy, const uint rc)
{
   if(!Exec_RetryableRetcode(rc)) return false;
   if(Exec_IsFailClosed(policy) && Exec_AmbiguousRetcode(rc)) return false;
   return true;
}

// Partial close normalization is floor-only: target can shrink for broker
// step/min constraints but must never exceed the requested close volume.
double Exec_CloseVolumeFloor(const double requestedVolume,
                             const double currentVolume,
                             const double volumeMin,
                             const double volumeStep)
{
   if(requestedVolume <= 0.0 || currentVolume <= 0.0 ||
      volumeMin <= 0.0 || volumeStep <= 0.0)
      return 0.0;

   double eps = volumeStep * 1e-7;
   if(requestedVolume + eps >= currentVolume)
      return NormalizeDouble(currentVolume, 8); // explicit full close

   long units = (long)MathFloor(requestedVolume / volumeStep + 1e-9);
   double target = (double)units * volumeStep;
   if(target + eps < volumeMin) return 0.0;
   if(target > requestedVolume + eps)
   {
      units--;
      if(units <= 0) return 0.0;
      target = (double)units * volumeStep;
   }

   double remaining = currentVolume - target;
   if(remaining > eps && remaining + eps < volumeMin)
   {
      double maxTarget = currentVolume - volumeMin;
      long maxUnits = (long)MathFloor(maxTarget / volumeStep + 1e-9);
      target = (double)maxUnits * volumeStep;
      if(target > requestedVolume + eps)
      {
         long reqUnits = (long)MathFloor(requestedVolume / volumeStep + 1e-9);
         target = (double)reqUnits * volumeStep;
      }
   }

   if(target <= 0.0 || target > requestedVolume + eps) return 0.0;
   return NormalizeDouble(target, 8);
}

class CExecutionLayer
{
private:
   PendingRequest m_journal[];
   ENUM_ORDER_TYPE_FILLING m_filling;
   bool m_asyncAllowed;
   bool m_busyOpenBuy;    // legacy Core busy flags only
   bool m_busyOpenSell;

   bool RetcodeOk(const uint rc) const
   {
      return rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_DONE_PARTIAL || rc == TRADE_RETCODE_PLACED;
   }

   ENUM_ORDER_TYPE_FILLING FillingFor(const string sym) const
   {
      long modes = SymbolInfoInteger(sym, SYMBOL_FILLING_MODE);
      if((modes & SYMBOL_FILLING_FOK) != 0) return ORDER_FILLING_FOK;
      if((modes & SYMBOL_FILLING_IOC) != 0) return ORDER_FILLING_IOC;
      return ORDER_FILLING_RETURN;
   }

   void DetectFilling() { m_filling = FillingFor(_Symbol); }

   int CountOpenPositions(const eIntent action, const string symbol, const long ownerMagic) const
   {
      if(action != INTENT_OPEN_BUY && action != INTENT_OPEN_SELL) return 0;
      long wanted = (action == INTENT_OPEN_BUY) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
      int count = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong tic = PositionGetTicket(i);
         if(tic == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) == symbol &&
            Exec_OwnerMatches(PositionGetInteger(POSITION_MAGIC), ownerMagic) &&
            PositionGetInteger(POSITION_TYPE) == wanted)
            count++;
      }
      return count;
   }

   bool AnyLiveOrder(const long ownerMagic, const string symbol) const
   {
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         ulong tic = OrderGetTicket(i);
         if(tic == 0) continue;
         if((symbol == "" || OrderGetString(ORDER_SYMBOL) == symbol) &&
            Exec_OwnerMatches(OrderGetInteger(ORDER_MAGIC), ownerMagic))
            return true;
      }
      return false;
   }

   int Journal_Add(const uint reqId,
                   const MqlTradeRequest &req,
                   const eIntent action,
                   const SExecRequestMeta &meta,
                   const int positionCountBefore,
                   const double positionVolumeBefore)
   {
      int n = ArraySize(m_journal);
      ArrayResize(m_journal, n + 1);
      m_journal[n].requestId = reqId;
      m_journal[n].ticket    = req.position;
      m_journal[n].symbol    = req.symbol;
      m_journal[n].action    = action;
      m_journal[n].phase     = PENDING_SENT;
      m_journal[n].volume    = req.volume;
      m_journal[n].targetVolume = req.volume;
      m_journal[n].observedVolume = 0;
      m_journal[n].positionVolumeBefore = positionVolumeBefore > 0 ? positionVolumeBefore : req.volume;
      m_journal[n].sl        = req.sl;
      m_journal[n].tp        = req.tp;
      m_journal[n].serverOrder = 0;
      m_journal[n].serverDeal  = 0;
      m_journal[n].lastObservedDeal = 0;
      m_journal[n].requestRetcode = 0;
      m_journal[n].positionCountBefore = positionCountBefore;
      m_journal[n].sentAt    = TimeCurrent();
      m_journal[n].retries   = 0;
      m_journal[n].ownerMagic = meta.ownerMagic;
      m_journal[n].cycleKey = meta.cycleKey;
      m_journal[n].commandType = meta.commandType;
      m_journal[n].reconcilePolicy = meta.reconcilePolicy;
      m_journal[n].reconcileRequired = false;
      m_journal[n].serverFinal = false;
      m_journal[n].orderDeleted = false;
      m_journal[n].active    = true;
      return n;
   }

   int Journal_Find(const uint reqId) const
   {
      if(reqId == 0) return -1;
      for(int i = ArraySize(m_journal) - 1; i >= 0; i--)
         if(m_journal[i].active && m_journal[i].requestId == reqId)
            return i;
      return -1;
   }

   void Journal_CompleteAt(const int i)
   {
      if(i < 0 || i >= ArraySize(m_journal) || !m_journal[i].active) return;
      m_journal[i].active = false;
      m_journal[i].reconcileRequired = false;
      // Keep historical Core busy semantics isolated from Recovery commands.
      if(m_journal[i].commandType == EXEC_CMD_LEGACY)
      {
         if(m_journal[i].action == INTENT_OPEN_BUY)  m_busyOpenBuy  = false;
         if(m_journal[i].action == INTENT_OPEN_SELL) m_busyOpenSell = false;
      }
   }

   bool Journal_ServerOrderLive(const PendingRequest &p) const
   {
      return p.serverOrder != 0 && OrderSelect(p.serverOrder);
   }

   bool Journal_StateResolved(const PendingRequest &p) const
   {
      if(p.action == INTENT_OPEN_BUY || p.action == INTENT_OPEN_SELL)
      {
         if(CountOpenPositions(p.action, p.symbol, p.ownerMagic) <= p.positionCountBefore) return false;
         if(Journal_ServerOrderLive(p)) return false;
         if(p.serverOrder == 0 && AnyLiveOrder(p.ownerMagic, p.symbol)) return false;
         return true;
      }

      if(p.action == INTENT_CLOSE_TICKET)
      {
         if(!PositionSelectByTicket(p.ticket)) return true;
         double step = SymbolInfoDouble(p.symbol, SYMBOL_VOLUME_STEP);
         double target = p.targetVolume > 0 ? p.targetVolume : p.volume;
         return Exec_CloseVolumeResolved(p.positionVolumeBefore,
                                         PositionGetDouble(POSITION_VOLUME),
                                         target, step);
      }

      if(p.action == INTENT_MODIFY_SLTP)
      {
         if(!PositionSelectByTicket(p.ticket)) return true;
         double point = SymbolInfoDouble(p.symbol, SYMBOL_POINT);
         double eps = point > 0 ? point * 0.5 : 1e-9;
         return MathAbs(PositionGetDouble(POSITION_SL) - p.sl) <= eps &&
                MathAbs(PositionGetDouble(POSITION_TP) - p.tp) <= eps;
      }
      return false;
   }

   bool Journal_DealMatches(const PendingRequest &p, const MqlTradeTransaction &trans) const
   {
      if(trans.type != TRADE_TRANSACTION_DEAL_ADD || trans.deal == 0) return false;
      if(p.serverDeal != 0 && p.serverDeal == trans.deal) return true;
      if(p.action == INTENT_CLOSE_TICKET)
         return trans.position == p.ticket;
      if(p.action != INTENT_OPEN_BUY && p.action != INTENT_OPEN_SELL) return false;
      if(!HistoryDealSelect(trans.deal)) return false;
      if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != p.symbol ||
         !Exec_OwnerMatches(HistoryDealGetInteger(trans.deal, DEAL_MAGIC), p.ownerMagic))
         return false;
      long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_IN && entry != DEAL_ENTRY_INOUT) return false;
      long type = HistoryDealGetInteger(trans.deal, DEAL_TYPE);
      return (p.action == INTENT_OPEN_BUY  && type == DEAL_TYPE_BUY) ||
             (p.action == INTENT_OPEN_SELL && type == DEAL_TYPE_SELL);
   }

   void Journal_TryCompleteAt(const int i)
   {
      if(i < 0 || i >= ArraySize(m_journal) || !m_journal[i].active) return;
      bool stateResolved = Journal_StateResolved(m_journal[i]);
      ePendingEvidence evidence = PENDING_EVIDENCE_NONE;
      if(m_journal[i].phase == PENDING_REQUEST_ACCEPTED) evidence = PENDING_EVIDENCE_REQUEST;
      if(m_journal[i].observedVolume > 0)                evidence = PENDING_EVIDENCE_DEAL;
      if(m_journal[i].orderDeleted)                      evidence = PENDING_EVIDENCE_ORDER_DELETE;
      if(stateResolved)                                  evidence = PENDING_EVIDENCE_RESULT_STATE;
      if(Exec_PendingReady(evidence))
         Journal_CompleteAt(i);
   }

   void Journal_ReconcileAll()
   {
      for(int i = ArraySize(m_journal) - 1; i >= 0; i--)
         Journal_TryCompleteAt(i);
   }

   void Journal_ApplyResult(const int i, const MqlTradeResult &res)
   {
      if(i < 0 || i >= ArraySize(m_journal)) return;
      m_journal[i].phase = PENDING_REQUEST_ACCEPTED;
      m_journal[i].requestRetcode = res.retcode;
      if(res.order != 0) m_journal[i].serverOrder = res.order;
      if(res.deal  != 0) m_journal[i].serverDeal  = res.deal;
      m_journal[i].serverFinal =
         (res.retcode == TRADE_RETCODE_DONE || res.retcode == TRADE_RETCODE_DONE_PARTIAL);
      if(res.volume > 0) m_journal[i].targetVolume = res.volume;
   }

   bool Send(MqlTradeRequest &req, MqlTradeResult &res, const eIntent action,
             const SExecRequestMeta &meta, const double positionVolumeBefore)
   {
      int positionCountBefore = CountOpenPositions(action, req.symbol, meta.ownerMagic);

      // Async path: fire and journal; confirmation arrives via broker state.
      if(m_asyncAllowed && ExecMode == exec_Async)
      {
         if(!OrderSendAsync(req, res) || res.retcode != TRADE_RETCODE_PLACED)
         {
            Log_Warn("Exec", "async" + (string)action, "OrderSendAsync rejected, retcode=" + (string)res.retcode);
            return false;
         }
         Journal_Add(res.request_id, req, action, meta, positionCountBefore, positionVolumeBefore);
         if(meta.commandType == EXEC_CMD_LEGACY)
         {
            if(action == INTENT_OPEN_BUY)  m_busyOpenBuy  = true;
            if(action == INTENT_OPEN_SELL) m_busyOpenSell = true;
         }
         return true;
      }

      // Sync path. Legacy behavior keeps the original retry policy. Strict
      // Recovery refuses blind retry after ambiguous timeout/connection.
      for(int attempt = 0; attempt < BD_MAX_SEND_RETRIES; attempt++)
      {
         if(attempt > 0 && req.action == TRADE_ACTION_DEAL)
         {
            MqlTick tick;
            if(!SymbolInfoTick(req.symbol, tick)) break;
            req.price = (req.type == ORDER_TYPE_BUY) ? tick.ask : tick.bid;
         }
         ResetLastError();
         bool ok = OrderSend(req, res);
         if(ok && RetcodeOk(res.retcode))
         {
            // Recovery commands retain correlation even in sync mode. Legacy
            // sync requests remain journal-free exactly as before T2.
            if(meta.commandType != EXEC_CMD_LEGACY)
            {
               int j = Journal_Add(res.request_id, req, action, meta,
                                   positionCountBefore, positionVolumeBefore);
               Journal_ApplyResult(j, res);
               Journal_TryCompleteAt(j);
            }
            return true;
         }

         if(Exec_IsFailClosed(meta.reconcilePolicy) && Exec_AmbiguousRetcode(res.retcode))
         {
            int j = Journal_Add(res.request_id, req, action, meta,
                                positionCountBefore, positionVolumeBefore);
            m_journal[j].requestRetcode = res.retcode;
            m_journal[j].reconcileRequired = true;
            Log_Warn("Exec", "strictsync", "strict command has ambiguous sync outcome retcode=" +
                     (string)res.retcode + " — no blind retry; reconciliation required");
            return false;
         }

         if(!Exec_RetryAllowed(meta.reconcilePolicy, res.retcode)) break;
      }
      Log_Warn("Exec", "send" + (string)action,
               "OrderSend failed retcode=" + (string)res.retcode + " comment=" + res.comment);
      return false;
   }

public:
   void Init()
   {
      DetectFilling();
      ArrayResize(m_journal, 0);
      m_asyncAllowed = !MQLInfoInteger(MQL_TESTER);
      m_busyOpenBuy  = false;
      m_busyOpenSell = false;
      if(ExecMode == exec_Async && !m_asyncAllowed)
         Log_Info("Exec", "tester detected: async mode falls back to sync");
   }

   bool BusyOpen(const int dir) const { return dir == 0 ? m_busyOpenBuy : m_busyOpenSell; }

   bool HasPendingClose(const ulong ticket) const
   {
      for(int i = ArraySize(m_journal) - 1; i >= 0; i--)
         if(m_journal[i].active && m_journal[i].action == INTENT_CLOSE_TICKET && m_journal[i].ticket == ticket)
            return true;
      return false;
   }

   bool HasAnyPendingClose() const
   {
      for(int i = ArraySize(m_journal) - 1; i >= 0; i--)
         if(m_journal[i].active && m_journal[i].action == INTENT_CLOSE_TICKET)
            return true;
      return false;
   }

   bool HasPendingModify(const ulong ticket) const
   {
      for(int i = ArraySize(m_journal) - 1; i >= 0; i--)
         if(m_journal[i].active && m_journal[i].action == INTENT_MODIFY_SLTP && m_journal[i].ticket == ticket)
            return true;
      return false;
   }

   bool HasPendingForCycle(const int cycleKey) const
   {
      if(cycleKey == 0) return false;
      for(int i = ArraySize(m_journal) - 1; i >= 0; i--)
         if(m_journal[i].active && m_journal[i].cycleKey == cycleKey)
            return true;
      return false;
   }

   bool HasReconcileRequired(const int cycleKey) const
   {
      if(cycleKey == 0) return false;
      for(int i = ArraySize(m_journal) - 1; i >= 0; i--)
         if(m_journal[i].active && m_journal[i].cycleKey == cycleKey &&
            m_journal[i].reconcileRequired)
            return true;
      return false;
   }

   void ReconcileCycle(const int cycleKey)
   {
      if(cycleKey == 0) return;
      for(int i = ArraySize(m_journal) - 1; i >= 0; i--)
         if(m_journal[i].active && m_journal[i].cycleKey == cycleKey)
            Journal_TryCompleteAt(i);
   }

   //--- Legacy market-open API: semantics retained -------------------------
   bool OpenMarket(const int dir, double volume, const int dcaIndex)
   {
      if(!License_Check()) return false;
      double requested = volume;
      volume = Grid_NormalizeVolume(volume);
      if(volume <= 0) return false;
      if(MathAbs(volume - requested) > 1e-12)
         Log_Info("Exec", "order #" + IntegerToString(dcaIndex) + " lot adjusted: requested " +
                  DoubleToString(requested, 3) + " -> using " + DoubleToString(volume, 3) +
                  " (symbol min/step/max limits)");
      MqlTick tick;
      if(!SymbolInfoTick(_Symbol, tick)) return false;
      MqlTradeRequest req; MqlTradeResult res;
      ZeroMemory(req); ZeroMemory(res);
      req.action       = TRADE_ACTION_DEAL;
      req.symbol       = _Symbol;
      req.volume       = volume;
      req.type         = (dir == 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      req.price        = (dir == 0) ? tick.ask : tick.bid;
      req.deviation    = Exec_Deviation(Slippage_, Cfg.PointScale);
      req.magic        = Magic;
      req.comment      = Exec_BuildComment(sOrdComm, dcaIndex);
      req.type_filling = m_filling;
      SExecRequestMeta meta;
      Exec_InitMeta(meta, (long)Magic, 0, EXEC_CMD_LEGACY, EXEC_RECONCILE_LEGACY_RELEASE);
      return Send(req, res, dir == 0 ? INTENT_OPEN_BUY : INTENT_OPEN_SELL, meta, 0.0);
   }

   //--- Owner-aware market-open primitive for later Recovery slices. -------
   bool OpenMarketOwned(const int dir, double volume,
                        const long ownerMagic, const int cycleKey,
                        const eExecCommandType commandType,
                        const eExecReconcilePolicy reconcilePolicy,
                        const string comment)
   {
      if(!License_Check() || ownerMagic <= 0 || cycleKey == 0) return false;
      volume = Grid_NormalizeVolume(volume);
      if(volume <= 0) return false;
      MqlTick tick;
      if(!SymbolInfoTick(_Symbol, tick)) return false;
      MqlTradeRequest req; MqlTradeResult res;
      ZeroMemory(req); ZeroMemory(res);
      req.action       = TRADE_ACTION_DEAL;
      req.symbol       = _Symbol;
      req.volume       = volume;
      req.type         = (dir == 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      req.price        = (dir == 0) ? tick.ask : tick.bid;
      req.deviation    = Exec_Deviation(Slippage_, Cfg.PointScale);
      req.magic        = (ulong)ownerMagic;
      req.comment      = comment;
      req.type_filling = m_filling;
      SExecRequestMeta meta;
      Exec_InitMeta(meta, ownerMagic, cycleKey, commandType, reconcilePolicy);
      return Send(req, res, dir == 0 ? INTENT_OPEN_BUY : INTENT_OPEN_SELL, meta, 0.0);
   }

   //--- Owner-aware partial/full close primitive ---------------------------
   bool ClosePositionVolumeOwned(const ulong ticket, const double requestedVolume,
                                 const long expectedOwnerMagic, const int cycleKey,
                                 const eExecCommandType commandType,
                                 const eExecReconcilePolicy reconcilePolicy)
   {
      if(!PositionSelectByTicket(ticket)) return false;
      if(m_asyncAllowed && ExecMode == exec_Async && HasPendingClose(ticket)) return false;

      string sym = PositionGetString(POSITION_SYMBOL);
      long type = PositionGetInteger(POSITION_TYPE);
      long positionMagic = PositionGetInteger(POSITION_MAGIC);
      if(!Exec_OwnerMatches(positionMagic, expectedOwnerMagic))
      {
         Log_Warn("Exec", "owner", "close ownership mismatch for #" + (string)ticket);
         return false;
      }

      double currentVolume = PositionGetDouble(POSITION_VOLUME);
      double step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
      double vMin = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
      double target = Exec_CloseVolumeFloor(requestedVolume, currentVolume, vMin, step);
      if(target <= 0.0) return false;

      MqlTick tick;
      if(!SymbolInfoTick(sym, tick)) return false;
      MqlTradeRequest req; MqlTradeResult res;
      ZeroMemory(req); ZeroMemory(res);
      req.action       = TRADE_ACTION_DEAL;
      req.symbol       = sym;
      req.position     = ticket;
      req.volume       = target;
      req.type         = (type == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
      req.price        = (type == POSITION_TYPE_BUY) ? tick.bid : tick.ask;
      req.deviation    = Exec_Deviation(Slippage_, Sym_PointScaleFor(sym));
      req.magic        = Exec_CloseRequestMagic(positionMagic);
      req.type_filling = FillingFor(sym);
      SExecRequestMeta meta;
      Exec_InitMeta(meta, positionMagic, cycleKey, commandType, reconcilePolicy);
      return Send(req, res, INTENT_CLOSE_TICKET, meta, currentVolume);
   }

   //--- Legacy close wrapper: same ticket/full-volume outcome, but request
   //    now preserves selected-position magic consistently with BD-R10.
   bool ClosePosition(const ulong ticket)
   {
      if(!PositionSelectByTicket(ticket)) return false;
      long positionMagic = PositionGetInteger(POSITION_MAGIC);
      double currentVolume = PositionGetDouble(POSITION_VOLUME);
      return ClosePositionVolumeOwned(ticket, currentVolume, positionMagic, 0,
                                      EXEC_CMD_LEGACY, EXEC_RECONCILE_LEGACY_RELEASE);
   }

   int CloseBasket(const BasketSide &side)
   {
      int sent = 0;
      for(int i = 0; i < side.count; i++)
         if(side.pos[i].ticket != 0 && ClosePosition(side.pos[i].ticket)) sent++;
      return sent;
   }

   bool ClosePositionEx(const ulong ticket)
   {
      if(!PositionSelectByTicket(ticket)) return false;
      long positionMagic = PositionGetInteger(POSITION_MAGIC);
      double currentVolume = PositionGetDouble(POSITION_VOLUME);
      return ClosePositionVolumeOwned(ticket, currentVolume, positionMagic, 0,
                                      EXEC_CMD_LEGACY, EXEC_RECONCILE_LEGACY_RELEASE);
   }

   int CloseAllAccount()
   {
      int sent = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong tic = PositionGetTicket(i);
         if(tic != 0 && ClosePositionEx(tic)) sent++;
      }
      if(sent > 0) Log_Info("Exec", "CloseAllAccount: " + (string)sent + " close request(s) sent (all symbols/magics)");
      return sent;
   }

   bool ModifySlTpOwned(const ulong ticket, const double sl, const double tp,
                        const long expectedOwnerMagic, const int cycleKey,
                        const eExecCommandType commandType,
                        const eExecReconcilePolicy reconcilePolicy)
   {
      if(!PositionSelectByTicket(ticket)) return false;
      if(m_asyncAllowed && ExecMode == exec_Async && HasPendingModify(ticket)) return false;
      string sym = PositionGetString(POSITION_SYMBOL);
      long positionMagic = PositionGetInteger(POSITION_MAGIC);
      if(!Exec_OwnerMatches(positionMagic, expectedOwnerMagic)) return false;
      MqlTradeRequest req; MqlTradeResult res;
      ZeroMemory(req); ZeroMemory(res);
      req.action   = TRADE_ACTION_SLTP;
      req.position = ticket;
      req.symbol   = sym;
      req.sl       = sl;
      req.tp       = tp;
      req.magic    = Exec_CloseRequestMagic(positionMagic);
      SExecRequestMeta meta;
      Exec_InitMeta(meta, positionMagic, cycleKey, commandType, reconcilePolicy);
      return Send(req, res, INTENT_MODIFY_SLTP, meta, PositionGetDouble(POSITION_VOLUME));
   }

   bool ModifySlTp(const ulong ticket, const double sl, const double tp)
   {
      if(!PositionSelectByTicket(ticket)) return false;
      long positionMagic = PositionGetInteger(POSITION_MAGIC);
      return ModifySlTpOwned(ticket, sl, tp, positionMagic, 0,
                             EXEC_CMD_LEGACY, EXEC_RECONCILE_LEGACY_RELEASE);
   }

   bool DeleteOrder(const ulong ticket)
   {
      MqlTradeRequest req; MqlTradeResult res;
      ZeroMemory(req); ZeroMemory(res);
      req.action = TRADE_ACTION_REMOVE;
      req.order  = ticket;
      ResetLastError();
      bool ok = OrderSend(req, res);
      if(ok && RetcodeOk(res.retcode)) return true;
      Log_Warn("Exec", "orddel", "delete pending #" + (string)ticket + " failed retcode=" + (string)res.retcode);
      return false;
   }

   void OnTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
   {
      if(trans.type == TRADE_TRANSACTION_REQUEST)
      {
         int i = Journal_Find(result.request_id);
         if(i >= 0)
         {
            if(!RetcodeOk(result.retcode))
            {
               Journal_CompleteAt(i); // explicit rejection is a proven outcome
               if(result.retcode != 0)
                  Log_Warn("Exec", "txrej", "async request rejected retcode=" + (string)result.retcode);
            }
            else
            {
               Journal_ApplyResult(i, result);
            }
         }
      }

      if(trans.type == TRADE_TRANSACTION_DEAL_ADD && trans.deal != 0)
      {
         for(int i = ArraySize(m_journal) - 1; i >= 0; i--)
            if(m_journal[i].active && Journal_DealMatches(m_journal[i], trans) &&
               m_journal[i].lastObservedDeal != trans.deal)
            {
               double dealVolume = trans.volume;
               if(HistoryDealSelect(trans.deal))
                  dealVolume = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);
               if(dealVolume > 0) m_journal[i].observedVolume += dealVolume;
               m_journal[i].lastObservedDeal = trans.deal;
            }
      }

      if(trans.type == TRADE_TRANSACTION_ORDER_DELETE && trans.order != 0)
      {
         for(int i = ArraySize(m_journal) - 1; i >= 0; i--)
            if(m_journal[i].active && m_journal[i].serverOrder != 0 &&
               m_journal[i].serverOrder == trans.order)
               m_journal[i].orderDeleted = true;
      }

      Journal_ReconcileAll();
   }

   bool HasLiveOrder() const
   {
      return AnyLiveOrder((long)Magic, _Symbol);
   }

   void Watchdog()
   {
      Journal_ReconcileAll();
      bool liveChecked = false, liveOrder = false;
      for(int i = ArraySize(m_journal) - 1; i >= 0; i--)
         if(m_journal[i].active && TimeCurrent() - m_journal[i].sentAt > BD_ASYNC_TIMEOUT_SEC)
         {
            if(m_journal[i].reconcileRequired) continue; // already surfaced once

            int elapsed = (int)(TimeCurrent() - m_journal[i].sentAt);
            int hardTimeout = Exec_HardTimeoutSec(m_journal[i].action);
            bool isOpen = (m_journal[i].action == INTENT_OPEN_BUY || m_journal[i].action == INTENT_OPEN_SELL);
            bool live = Journal_ServerOrderLive(m_journal[i]);
            if(isOpen && !live)
            {
               if(m_journal[i].commandType == EXEC_CMD_LEGACY)
               {
                  if(!liveChecked) { liveOrder = HasLiveOrder(); liveChecked = true; }
                  live = liveOrder;
               }
               else
                  live = AnyLiveOrder(m_journal[i].ownerMagic, m_journal[i].symbol);
            }
            if(live)
            {
               m_journal[i].retries++;
               Log_Warn("Exec", "wdoglive", "async request past soft timeout but its broker order is still live — guard stays locked");
               continue;
            }
            if(elapsed <= hardTimeout)
            {
               m_journal[i].retries++;
               Log_Warn("Exec", "wdogwait", "async request past soft timeout without final observable state — reconciling, guard stays locked");
               continue;
            }

            Journal_TryCompleteAt(i);
            if(!m_journal[i].active) continue;

            if(Exec_IsFailClosed(m_journal[i].reconcilePolicy))
            {
               m_journal[i].reconcileRequired = true;
               m_journal[i].retries++;
               Log_Warn("Exec", "wdogstrict", "strict request " + (string)m_journal[i].requestId +
                        " unresolved after " + (string)hardTimeout +
                        "s — FAIL-CLOSED, reconciliation required");
               continue;
            }

            // Exact legacy bounded-release policy retained.
            Journal_CompleteAt(i);
            Log_Warn("Exec", "wdog", "async request " + (string)m_journal[i].requestId +
                     " unresolved after " + (string)hardTimeout +
                     "s — guard released after final reconciliation");
         }

      int n = ArraySize(m_journal);
      if(n > 64)
      {
         int w = 0;
         for(int i = 0; i < n; i++)
            if(m_journal[i].active) { m_journal[w] = m_journal[i]; w++; }
         ArrayResize(m_journal, w);
      }
   }

   bool HasPending() const
   {
      for(int i = ArraySize(m_journal) - 1; i >= 0; i--)
         if(m_journal[i].active) return true;
      return false;
   }
};
#endif // BD_EXECUTIONLAYER_MQH
