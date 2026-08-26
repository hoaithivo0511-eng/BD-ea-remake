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
//|             BD-R1 CLOSE/MODIFY unlock 10s, OPEN keeps 30s.       |
//| Depends on: Types.mqh, GridEngine.mqh, Logger.mqh, License.mqh   |
//+------------------------------------------------------------------+
#ifndef BD_EXECUTIONLAYER_MQH
#define BD_EXECUTIONLAYER_MQH
#include "Types.mqh"
#include "GridEngine.mqh"
#include "Logger.mqh"
#include "License.mqh"

//--- FE-203: order comment carries the DCA order index: "comment|n"
//    (n = 1-based position in the series; 0 = plain comment). Pure,
//    unit-tested. The EA never parses comments back (C6) — this is for
//    humans and external tools reading the deal list.
string Exec_BuildComment(const string baseComment, const int dcaIndex)
{
   if(dcaIndex <= 0) return baseComment;
   return baseComment + "|" + IntegerToString(dcaIndex);
}

//--- BD-002: pure lifecycle rule, shared by MQL and offline tests.
//    REQUEST acceptance alone is never enough. Completion needs an observed
//    resulting broker state. Event metadata alone is insufficient because
//    transaction arrival order is not guaranteed.
bool Exec_PendingReady(const ePendingEvidence evidence)
{
   return evidence == PENDING_EVIDENCE_RESULT_STATE;
}

//--- BD-R2 (v14.7.2): PURE deviation scaling --------------------------
//    Slippage_ is a point-based input exactly like TP_/SL_/iTS/iTD, so it
//    must obey ARCHITECTURE rule 8 and be expressed in BROKER points at the
//    send site. Before this fix `req.deviation = Slippage_` was the only
//    point-input bypassing PointScale: on a 3-digit gold quote Slippage_=3
//    allowed 0.03 USD of slip instead of the intended 0.30 USD, so requests
//    were rejected/requoted far more often than on a 2-digit feed.
//    Clamps: negative slippage -> 0, scale < 1 -> 1 (never widen silently).
ulong Exec_Deviation(const int slippagePoints, const int pointScale)
{
   int s = slippagePoints < 0 ? 0 : slippagePoints;
   int k = pointScale < 1 ? 1 : pointScale;
   return (ulong)(s * k);
}

//--- BD-R1 (v14.7.2, quyet dinh Chu nha 11/08/2026) -------------------
//    PURE per-intent hard timeout for the watchdog's final unlock.
//    Strategy::OnTick suppresses the WHOLE tick — MoneyGuard included —
//    while any async CLOSE is still unresolved. A lost close reply therefore
//    froze the money / daily stops for BD_ASYNC_HARD_TIMEOUT_SEC (30s).
//    Chu nha's decision: KEEP that ordering (a guard close fired on top of an
//    unresolved close would double the exit traffic) and shorten the window
//    instead. The asymmetry is deliberate and safe:
//      - CLOSE and MODIFY are idempotent. ClosePosition() re-selects the
//        ticket and returns false when the position is already gone;
//        ModifySlTp() re-sends identical levels. Releasing the journal slot
//        early can at worst repeat a harmless request -> 10s.
//      - OPEN is NOT idempotent. Releasing m_busyOpen* early could put a
//        SECOND real order on the book -> keeps the conservative 30s.
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

//--- BD-R10 (deep review 14/08/2026): preserve close ownership ------
//    A zero-initialized MqlTradeRequest makes the closing DEAL magic 0.
//    CloseAllAccount() can close this EA, manual, and foreign-EA positions,
//    so assigning the chart Magic to every request would corrupt ownership
//    in the opposite direction. Preserve the selected position's magic:
//    own positions stay owned, manual stays 0, foreign stays foreign.
ulong Exec_CloseRequestMagic(const long positionMagic)
{
   return positionMagic > 0 ? (ulong)positionMagic : 0;
}

class CExecutionLayer
{
private:
   PendingRequest m_journal[];
   ENUM_ORDER_TYPE_FILLING m_filling;
   bool m_asyncAllowed;
   bool m_busyOpenBuy;    // fix #6: per-direction, not global
   bool m_busyOpenSell;

   //--- retcodes that mean "done / accepted"
   bool RetcodeOk(const uint rc) const
   {
      return rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_DONE_PARTIAL || rc == TRADE_RETCODE_PLACED;
   }
   //--- retcodes worth retrying with a fresh price
   bool RetcodeRetryable(const uint rc) const
   {
      return rc == TRADE_RETCODE_REQUOTE || rc == TRADE_RETCODE_PRICE_CHANGED ||
             rc == TRADE_RETCODE_PRICE_OFF || rc == TRADE_RETCODE_TIMEOUT ||
             rc == TRADE_RETCODE_CONNECTION;
   }

   //--- FE-401 (v14.3): per-symbol filling detection (CloseAllAccount can
   //    touch positions on ANY symbol, each with its own filling rules)
   ENUM_ORDER_TYPE_FILLING FillingFor(const string sym) const
   {
      long modes = SymbolInfoInteger(sym, SYMBOL_FILLING_MODE);
      if((modes & SYMBOL_FILLING_FOK) != 0) return ORDER_FILLING_FOK;
      if((modes & SYMBOL_FILLING_IOC) != 0) return ORDER_FILLING_IOC;
      return ORDER_FILLING_RETURN;
   }

   void DetectFilling() { m_filling = FillingFor(_Symbol); }

   int CountOpenPositions(const eIntent action, const string symbol) const
   {
      if(action != INTENT_OPEN_BUY && action != INTENT_OPEN_SELL) return 0;
      long wanted = (action == INTENT_OPEN_BUY) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
      int count = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong tic = PositionGetTicket(i);
         if(tic == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) == symbol &&
            PositionGetInteger(POSITION_MAGIC) == Magic &&
            PositionGetInteger(POSITION_TYPE) == wanted)
            count++;
      }
      return count;
   }

   bool AnyLiveOrder() const
   {
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         ulong tic = OrderGetTicket(i);
         if(tic == 0) continue;
         if(OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == Magic)
            return true;
      }
      return false;
   }

   void Journal_Add(const uint reqId, const MqlTradeRequest &req, const eIntent action)
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
      m_journal[n].positionVolumeBefore = req.volume;
      m_journal[n].sl        = req.sl;
      m_journal[n].tp        = req.tp;
      m_journal[n].serverOrder = 0;
      m_journal[n].serverDeal  = 0;
      m_journal[n].lastObservedDeal = 0;
      m_journal[n].requestRetcode = 0;
      m_journal[n].positionCountBefore = CountOpenPositions(action, req.symbol);
      m_journal[n].sentAt    = TimeCurrent();
      m_journal[n].retries   = 0;
      m_journal[n].serverFinal = false;
      m_journal[n].orderDeleted = false;
      m_journal[n].active    = true;
   }

   int Journal_Find(const uint reqId) const
   {
      for(int i = ArraySize(m_journal) - 1; i >= 0; i--)
         if(m_journal[i].active && m_journal[i].requestId == reqId)
            return i;
      return -1;
   }

   void Journal_CompleteAt(const int i)
   {
      if(i < 0 || i >= ArraySize(m_journal) || !m_journal[i].active) return;
      m_journal[i].active = false;
      if(m_journal[i].action == INTENT_OPEN_BUY)  m_busyOpenBuy  = false;
      if(m_journal[i].action == INTENT_OPEN_SELL) m_busyOpenSell = false;
   }

   bool Journal_ServerOrderLive(const PendingRequest &p) const
   {
      return p.serverOrder != 0 && OrderSelect(p.serverOrder);
   }

   bool Journal_StateResolved(const PendingRequest &p) const
   {
      if(p.action == INTENT_OPEN_BUY || p.action == INTENT_OPEN_SELL)
      {
         if(CountOpenPositions(p.action, p.symbol) <= p.positionCountBefore) return false;
         // A partial fill can create the position while the remainder is still
         // working. Keep the busy guard until no broker order is live.
         if(Journal_ServerOrderLive(p)) return false;
         if(p.serverOrder == 0 && AnyLiveOrder()) return false;
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
         if(!PositionSelectByTicket(p.ticket)) return true;  // position closed elsewhere
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
         HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != Magic)
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

   bool Send(MqlTradeRequest &req, MqlTradeResult &res, const eIntent action)
   {
      // Async path: fire and journal; confirmation arrives in OnTradeTransaction
      if(m_asyncAllowed && ExecMode == exec_Async)
      {
         if(!OrderSendAsync(req, res) || res.retcode != TRADE_RETCODE_PLACED)
         {
            Log_Warn("Exec", "async" + (string)action, "OrderSendAsync rejected, retcode=" + (string)res.retcode);
            return false;
         }
         Journal_Add(res.request_id, req, action);
         if(action == INTENT_OPEN_BUY)  m_busyOpenBuy  = true;
         if(action == INTENT_OPEN_SELL) m_busyOpenSell = true;
         return true;
      }
      // Sync path: up to BD_MAX_SEND_RETRIES, refresh price each attempt (fix #6), never Sleep (fix #7)
      for(int attempt = 0; attempt < BD_MAX_SEND_RETRIES; attempt++)
      {
         if(attempt > 0 && req.action == TRADE_ACTION_DEAL)
         {
            MqlTick tick;
            if(!SymbolInfoTick(req.symbol, tick)) break;   // FE-401: request's own symbol (CloseAllAccount is cross-symbol)
            req.price = (req.type == ORDER_TYPE_BUY) ? tick.ask : tick.bid;
         }
         ResetLastError();
         bool ok = OrderSend(req, res);
         if(ok && RetcodeOk(res.retcode)) return true;              // fix #1: retcode verified
         if(!RetcodeRetryable(res.retcode)) break;
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
      // OrderSendAsync gives no benefit and complicates the strategy tester -> force sync there
      m_asyncAllowed = !MQLInfoInteger(MQL_TESTER);
      m_busyOpenBuy  = false;
      m_busyOpenSell = false;
      if(ExecMode == exec_Async && !m_asyncAllowed)
         Log_Info("Exec", "tester detected: async mode falls back to sync");
   }

   bool BusyOpen(const int dir) const { return dir == 0 ? m_busyOpenBuy : m_busyOpenSell; }

   //--- audit fix: an async close already in flight for this ticket?
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

   //--- AU-14-02: an async SL/TP modify already in flight for this ticket?
   //    Mirrors HasPendingClose — without it, Real-mode + Async re-sends the
   //    same modify every tick until the server confirmation arrives.
   bool HasPendingModify(const ulong ticket) const
   {
      for(int i = ArraySize(m_journal) - 1; i >= 0; i--)
         if(m_journal[i].active && m_journal[i].action == INTENT_MODIFY_SLTP && m_journal[i].ticket == ticket)
            return true;
      return false;
   }

   //--- Market open. dcaIndex = 1-based order number in the DCA series ---
   bool OpenMarket(const int dir, double volume, const int dcaIndex)
   {
      if(!License_Check()) return false;
      double requested = volume;
      volume = Grid_NormalizeVolume(volume);
      if(volume <= 0) return false;
      // FIX-5 rev (14.2.2): below-min lots trade at the broker MINIMUM (v13
      // clamp) instead of stopping the EA — but every adjusted order is
      // logged (un-throttled) so Chu nha can track them in the journal.
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
      req.deviation    = Exec_Deviation(Slippage_, Cfg.PointScale); // AU-14-06 input + BD-R2 point scale
      req.magic        = Magic;
      req.comment      = Exec_BuildComment(sOrdComm, dcaIndex);   // FE-203
      req.type_filling = m_filling;
      return Send(req, res, dir == 0 ? INTENT_OPEN_BUY : INTENT_OPEN_SELL);
   }

   //--- Close one position ----------------------------------------------
   bool ClosePosition(const ulong ticket)
   {
      if(!PositionSelectByTicket(ticket)) return false;   // already gone
      // audit fix: async mode — exit conditions stay true until the close fills;
      // without this guard the strategy re-sends the same close every tick.
      if(m_asyncAllowed && ExecMode == exec_Async && HasPendingClose(ticket)) return false;
      MqlTick tick;
      if(!SymbolInfoTick(_Symbol, tick)) return false;
      long type = PositionGetInteger(POSITION_TYPE);
      MqlTradeRequest req; MqlTradeResult res;
      ZeroMemory(req); ZeroMemory(res);
      req.action       = TRADE_ACTION_DEAL;
      req.symbol       = _Symbol;
      req.position     = ticket;
      req.volume       = PositionGetDouble(POSITION_VOLUME);
      req.type         = (type == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
      req.price        = (type == POSITION_TYPE_BUY) ? tick.bid : tick.ask;
      req.deviation    = Exec_Deviation(Slippage_, Cfg.PointScale); // AU-14-06 + BD-R2
      req.magic        = Magic;
      req.type_filling = m_filling;
      return Send(req, res, INTENT_CLOSE_TICKET);
   }

   //--- Close a whole side. Async mode: all requests leave in parallel. --
   int CloseBasket(const BasketSide &side)
   {
      int sent = 0;
      for(int i = 0; i < side.count; i++)
         if(side.pos[i].ticket != 0 && ClosePosition(side.pos[i].ticket)) sent++;
      return sent;
   }

   //--- FE-401 (v14.3): close ONE position of ANY symbol/magic ------------
   //    Used only by Money TP/SL All account. Same retry/journal machinery;
   //    HasPendingClose guards duplicates per ticket in async mode.
   bool ClosePositionEx(const ulong ticket)
   {
      if(!PositionSelectByTicket(ticket)) return false;
      if(m_asyncAllowed && ExecMode == exec_Async && HasPendingClose(ticket)) return false;
      string sym = PositionGetString(POSITION_SYMBOL);
      MqlTick tick;
      if(!SymbolInfoTick(sym, tick)) return false;
      long type = PositionGetInteger(POSITION_TYPE);
      long positionMagic = PositionGetInteger(POSITION_MAGIC);
      MqlTradeRequest req; MqlTradeResult res;
      ZeroMemory(req); ZeroMemory(res);
      req.action       = TRADE_ACTION_DEAL;
      req.symbol       = sym;
      req.position     = ticket;
      req.volume       = PositionGetDouble(POSITION_VOLUME);
      req.type         = (type == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
      req.price        = (type == POSITION_TYPE_BUY) ? tick.bid : tick.ask;
      // BD-R2: cross-symbol path — scale with THAT symbol's point size, not the chart's.
      req.deviation    = Exec_Deviation(Slippage_, Sym_PointScaleFor(sym));
      req.magic        = Exec_CloseRequestMagic(positionMagic);  // BD-R10: preserve owner
      req.type_filling = FillingFor(sym);
      return Send(req, res, INTENT_CLOSE_TICKET);
   }

   //--- FE-401 (v14.3): Money TP/SL All account — close EVERYTHING --------
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

   //--- Modify SL/TP (real mode) -----------------------------------------
   bool ModifySlTp(const ulong ticket, const double sl, const double tp)
   {
      // AU-14-02: async mode — cached sl/tp stay stale until the server
      // confirms; don't queue a duplicate modify for the same ticket.
      if(m_asyncAllowed && ExecMode == exec_Async && HasPendingModify(ticket)) return false;
      MqlTradeRequest req; MqlTradeResult res;
      ZeroMemory(req); ZeroMemory(res);
      req.action   = TRADE_ACTION_SLTP;
      req.position = ticket;
      req.symbol   = _Symbol;
      req.sl       = sl;
      req.tp       = tp;
      return Send(req, res, INTENT_MODIFY_SLTP);
   }

   //--- FE-404 (v14.5): remove a pending order (mobile-control cleanup).
   //    Deletes are rare and user-initiated -> always synchronous, even in
   //    async mode (runs on the timer path, never blocks a tick). A failed
   //    delete self-heals: the order is re-detected on the next scan.
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

   //--- OnTradeTransaction hook: advance/reconcile the async lifecycle -----
   void OnTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
   {
      if(trans.type == TRADE_TRANSACTION_REQUEST)
      {
         int i = Journal_Find(result.request_id);
         if(i >= 0)
         {
            if(!RetcodeOk(result.retcode))
            {
               // A rejected request has a terminal outcome and may release.
               Journal_CompleteAt(i);
               if(result.retcode != 0)
                  Log_Warn("Exec", "txrej", "async request rejected retcode=" + (string)result.retcode);
            }
            else
            {
               // BD-002: accepted is NOT completed. DEAL/ORDER/POSITION may
               // arrive before or after this callback.
               m_journal[i].phase = PENDING_REQUEST_ACCEPTED;
               m_journal[i].requestRetcode = result.retcode;
               if(result.order != 0) m_journal[i].serverOrder = result.order;
               if(result.deal  != 0) m_journal[i].serverDeal  = result.deal;
               m_journal[i].serverFinal =
                  (result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_DONE_PARTIAL);
               if(result.volume > 0) m_journal[i].targetVolume = result.volume;
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

   //--- FIX-1 (14.2.1): any working order of ours still at the broker?
   bool HasLiveOrder() const
   {
      return AnyLiveOrder();
   }

   //--- OnTimer watchdog: requests without server reply --------------------
   void Watchdog()
   {
      Journal_ReconcileAll();
      bool liveChecked = false, liveOrder = false;
      for(int i = ArraySize(m_journal) - 1; i >= 0; i--)
         if(m_journal[i].active && TimeCurrent() - m_journal[i].sentAt > BD_ASYNC_TIMEOUT_SEC)
         {
            int elapsed = (int)(TimeCurrent() - m_journal[i].sentAt);
            // BD-R1 (v14.7.2): CLOSE/MODIFY unlock at 10s, OPEN keeps 30s.
            int hardTimeout = Exec_HardTimeoutSec(m_journal[i].action);
            bool isOpen = (m_journal[i].action == INTENT_OPEN_BUY || m_journal[i].action == INTENT_OPEN_SELL);
            bool live = Journal_ServerOrderLive(m_journal[i]);
            if(isOpen && !live)
            {
               if(!liveChecked) { liveOrder = HasLiveOrder(); liveChecked = true; }
               live = liveOrder;
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

            // Bounded recovery: after a second, conservative timeout and one
            // final reconciliation, release instead of deadlocking forever.
            Journal_TryCompleteAt(i);
            if(!m_journal[i].active) continue;
            Journal_CompleteAt(i);
            Log_Warn("Exec", "wdog", "async request " + (string)m_journal[i].requestId +
                     " unresolved after " + (string)hardTimeout +
                     "s — guard released after final reconciliation");
         }
      // compact journal occasionally
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
