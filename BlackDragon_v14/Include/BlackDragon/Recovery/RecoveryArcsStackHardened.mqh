//+------------------------------------------------------------------+
//| RecoveryArcsStackHardened.mqh — T16.1 event-order/SL hardening   |
//| Prevents: broker SL effect -> premature Gnext -> late DEAL_ADD   |
//| being misclassified as manual/external mutation.                 |
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_ARCS_STACK_HARDENED_MQH
#define BD_RECOVERY_ARCS_STACK_HARDENED_MQH

#define private protected
#define CRecoveryArcsStack CRecoveryArcsStackBase
#include "RecoveryArcsStack.mqh"
#undef CRecoveryArcsStack
#undef private

#define BD_ARCS_PROTECTIVE_WAIT_TIMEOUT_SEC 10

struct SArcsHardeningCloseDeal
{
   ulong  deal;
   ulong  positionId;
   long   type;
   long   reason;
   double programmedSl;
   double dealPrice;
   double volume;
};

class CRecoveryArcsStack : public CRecoveryArcsStackBase
{
private:
   bool RecoveryPositionIdentity(const ulong positionId,
                                 int &generation,
                                 ulong &positionTicket) const
   {
      generation = -1;
      positionTicket = 0;
      if(positionId == 0 || !HistorySelectByPosition(positionId)) return false;

      ulong oldestDeal = 0;
      long oldestMsc = 0;
      long owner = 0;
      int g = -1;
      ulong openingOrder = 0;
      for(int i = 0; i < HistoryDealsTotal(); i++)
      {
         ulong deal = HistoryDealGetTicket(i);
         if(deal == 0 || HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol) continue;
         long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
         if(entry != DEAL_ENTRY_IN && entry != DEAL_ENTRY_INOUT) continue;
         long tmsc = HistoryDealGetInteger(deal, DEAL_TIME_MSC);
         if(oldestDeal == 0 || tmsc < oldestMsc ||
            (tmsc == oldestMsc && deal < oldestDeal))
         {
            oldestDeal = deal;
            oldestMsc = tmsc;
            owner = HistoryDealGetInteger(deal, DEAL_MAGIC);
            openingOrder = (ulong)HistoryDealGetInteger(deal, DEAL_ORDER);
            g = Recovery_ArcsGenerationFromComment(HistoryDealGetString(deal, DEAL_COMMENT));
         }
      }
      if(owner != (long)RecoveryMagic_ || g < 1) return false;
      generation = g;
      positionTicket = openingOrder;
      return true;
   }

   bool DealDirection(const long dealType,
                      eRecoveryCoreDirection &dir) const
   {
      // Closing a SELL Recovery Hedge is a BUY deal => BUY Core cycle.
      if(dealType == DEAL_TYPE_BUY)
      {
         dir = recovery_CORE_BUY;
         return true;
      }
      // Closing a BUY Recovery Hedge is a SELL deal => SELL Core cycle.
      if(dealType == DEAL_TYPE_SELL)
      {
         dir = recovery_CORE_SELL;
         return true;
      }
      return false;
   }

   bool IsExpectedPersistedProtectiveClose(const eRecoveryCoreDirection dir,
                                           const SArcsLayer &layer,
                                           const SArcsHardeningCloseDeal &d) const
   {
      double target = m_dir[Idx(dir)].globalSlArmed && m_dir[Idx(dir)].globalSlPrice > 0.0
                      ? m_dir[Idx(dir)].globalSlPrice
                      : (layer.virtualSlArmed && layer.virtualSlPrice > 0.0
                         ? layer.virtualSlPrice : layer.lockTargetPrice);
      if(target <= 0.0) return false;

      if(HedgeSLMode_ == SL_BROKER)
      {
         if(d.reason != DEAL_REASON_SL || d.programmedSl <= 0.0) return false;
         double tol = MathMax(2.0 * m_tickSize, _Point);
         return MathAbs(d.programmedSl - target) <= tol;
      }

      return HedgeSLMode_ == SL_VIRTUAL && layer.virtualSlArmed &&
             d.reason == DEAL_REASON_EXPERT;
   }

   bool RepairProtectiveLayerDecreases(const eRecoveryCoreDirection dir,
                                       string &why)
   {
      why = "";
      int di = Idx(dir);
      if(!HistorySelect(0, TimeCurrent()))
      {
         why = "không đọc được history để reconcile protective ARCS layer";
         return false;
      }

      ulong deals[];
      ArrayResize(deals, 0);
      for(int i = 0; i < HistoryDealsTotal(); i++)
      {
         ulong deal = HistoryDealGetTicket(i);
         if(deal == 0 || HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol) continue;
         long tmsc = HistoryDealGetInteger(deal, DEAL_TIME_MSC);
         if(!CursorAfter(tmsc, deal, m_dir[di].lastDealTimeMsc,
                         m_dir[di].lastDealTicket)) continue;
         long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
         if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY) continue;
         int n = ArraySize(deals);
         ArrayResize(deals, n + 1);
         deals[n] = deal;
      }

      for(int li = 0; li < BD_ARCS_MAX_LAYERS; li++)
      {
         SArcsLayer layer;
         GetLayer(dir, li, layer);
         if(!layer.used || layer.remainingUnits <= 0) continue;
         if(layer.state != ARCS_LAYER_LOCKED &&
            layer.state != ARCS_LAYER_GLOBAL_PROTECTED &&
            layer.state != ARCS_LAYER_PROTECTIVE_CLOSE_PENDING)
            continue;

         long live = Recovery_ArcsLayerUnits(dir, layer.generation, m_volumeStep);
         if(live == layer.remainingUnits) continue;
         if(live < 0 || live > layer.remainingUnits)
         {
            why = "protective layer broker volume tăng/không hợp lệ so với persisted ownership";
            return false;
         }

         long observedClose = layer.remainingUnits - live;
         long provenClose = 0;
         for(int k = 0; k < ArraySize(deals); k++)
         {
            ulong deal = deals[k];
            if(!HistoryDealSelect(deal)) continue;
            ulong positionId = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
            int generation = -1;
            ulong positionTicket = 0;
            if(!RecoveryPositionIdentity(positionId, generation, positionTicket) ||
               generation != layer.generation)
               continue;
            if(!HistoryDealSelect(deal)) continue;

            SArcsHardeningCloseDeal d;
            d.deal = deal;
            d.positionId = positionId;
            d.type = HistoryDealGetInteger(deal, DEAL_TYPE);
            d.reason = HistoryDealGetInteger(deal, DEAL_REASON);
            d.programmedSl = HistoryDealGetDouble(deal, DEAL_SL);
            d.dealPrice = HistoryDealGetDouble(deal, DEAL_PRICE);
            d.volume = HistoryDealGetDouble(deal, DEAL_VOLUME);
            if(!IsExpectedPersistedProtectiveClose(dir, layer, d)) continue;
            provenClose += Recovery_VolumeToUnitsFloor(d.volume, m_volumeStep);
         }

         if(provenClose != observedClose)
         {
            why = "persisted protective layer giảm volume nhưng không có exact protective-close proof";
            return false;
         }

         layer.remainingUnits = live;
         if(live == 0)
         {
            layer.state = ARCS_LAYER_CLOSED;
            layer.virtualSlArmed = false;
            if(m_dir[di].activeLayer == li &&
               m_dir[di].phase == ARCS_PROTECTIVE_CLOSE_WAIT)
               m_dir[di].phase = ARCS_LOCKED;
         }
         PutLayer(dir, li, layer);
      }
      return true;
   }

   void RefreshClosedGenerationFromDeal(const MqlTradeTransaction &trans)
   {
      if(trans.deal == 0 || !HistoryDealSelect(trans.deal)) return;
      long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY) return;
      ulong positionId = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
      long type = HistoryDealGetInteger(trans.deal, DEAL_TYPE);
      long reason = HistoryDealGetInteger(trans.deal, DEAL_REASON);
      if(positionId == 0) return;

      int generation = -1;
      ulong positionTicket = 0;
      if(!RecoveryPositionIdentity(positionId, generation, positionTicket)) return;
      if(!HistoryDealSelect(trans.deal)) return;

      eRecoveryCoreDirection dir;
      if(!DealDirection(type, dir)) return;
      int li = FindLayerByGeneration(dir, generation);
      if(li < 0) return;
      SArcsLayer layer;
      GetLayer(dir, li, layer);

      if(layer.state != ARCS_LAYER_LOCK_PENDING &&
         layer.state != ARCS_LAYER_PROTECTIVE_CLOSE_PENDING &&
         layer.state != ARCS_LAYER_LOCKED &&
         layer.state != ARCS_LAYER_GLOBAL_PROTECTED)
         return;

      bool expected = false;
      if(HedgeSLMode_ == SL_BROKER && reason == DEAL_REASON_SL)
         expected = ExpectedBrokerSlDeal(trans.deal);
      else if(HedgeSLMode_ == SL_VIRTUAL && reason == DEAL_REASON_EXPERT &&
              layer.virtualSlArmed)
         expected = true;
      if(!expected) return;

      long live = Recovery_ArcsLayerUnits(dir, generation, m_volumeStep);
      if(live < 0 || live > layer.remainingUnits)
      {
         LatchReconcile(dir, "post-deal protective layer volume violates persisted ownership");
         return;
      }

      layer.remainingUnits = live;
      if(live == 0)
      {
         layer.state = ARCS_LAYER_CLOSED;
         layer.virtualSlArmed = false;
         if(m_dir[Idx(dir)].activeLayer == li &&
            (m_dir[Idx(dir)].phase == ARCS_PROTECTIVE_CLOSE_WAIT ||
             m_dir[Idx(dir)].phase == ARCS_LOCK_PENDING))
            m_dir[Idx(dir)].phase = ARCS_LOCKED;
      }
      PutLayer(dir, li, layer);
   }

   void NormalizeStableLockedHold(const eRecoveryCoreDirection dir)
   {
      int di = Idx(dir);
      if(m_dir[di].phase != ARCS_LOCKED || m_dir[di].activeLayer < 0) return;
      long core = Recovery_ArcsCoreUnits(dir, m_volumeStep);
      bool terminalByMax = m_dir[di].generationCount >= MaxHedgeGenerations_;
      bool noCoreForNext = core <= 0;
      if(!terminalByMax && !noCoreForNext) return;
      m_dir[di].activeLayer = -1;
      m_dirty = true;
   }

   bool EnterProtectiveCloseWait(const eRecoveryCoreDirection dir,
                                 const EAContext &ctx,
                                 string &why)
   {
      int di = Idx(dir);
      if(m_dir[di].phase != ARCS_LOCK_PENDING || m_dir[di].activeLayer < 0)
         return false;
      int li = m_dir[di].activeLayer;
      SArcsLayer layer;
      GetLayer(dir, li, layer);
      if(!layer.used || layer.state != ARCS_LAYER_LOCK_PENDING ||
         layer.remainingUnits <= 0)
         return false;

      long live = Recovery_ArcsLayerUnits(dir, layer.generation, m_volumeStep);
      if(live > 0) return false;

      // A retained layer vanished while the FSM was still confirming its
      // broker lock. Do NOT mark it CLOSED or start Gnext from position state
      // alone. The corresponding DEAL_ADD must classify first.
      if(layer.lockTargetPrice <= 0.0)
      {
         why = "retained Hedge biến mất trước khi có durable lock target";
         LatchReconcile(dir, why);
         Save(why);
         return true;
      }

      layer.state = ARCS_LAYER_PROTECTIVE_CLOSE_PENDING;
      layer.protectiveCloseObservedAt = ctx.now;
      PutLayer(dir, li, layer);
      m_dir[di].phase = ARCS_PROTECTIVE_CLOSE_WAIT;
      m_dirty = true;
      if(!Save(why)) return true;
      Log_Info("Recovery", "T16.1 " + Recovery_DirectionName(dir) +
               " protective broker effect observed; waiting exact DEAL_ADD before next generation");
      return true;
   }

   bool HoldProtectiveCloseWait(const eRecoveryCoreDirection dir,
                                const EAContext &ctx,
                                string &why)
   {
      int di = Idx(dir);
      if(m_dir[di].phase != ARCS_PROTECTIVE_CLOSE_WAIT) return false;
      int li = m_dir[di].activeLayer;
      if(li < 0)
      {
         why = "PROTECTIVE_CLOSE_WAIT mất active layer identity";
         LatchReconcile(dir, why);
         Save(why);
         return true;
      }
      SArcsLayer layer;
      GetLayer(dir, li, layer);
      if(!layer.used || layer.state != ARCS_LAYER_PROTECTIVE_CLOSE_PENDING)
      {
         why = "PROTECTIVE_CLOSE_WAIT layer state mismatch";
         LatchReconcile(dir, why);
         Save(why);
         return true;
      }

      long live = Recovery_ArcsLayerUnits(dir, layer.generation, m_volumeStep);
      if(live > 0)
      {
         why = "protective-close wait broker exposure reappeared";
         LatchReconcile(dir, why);
         Save(why);
         return true;
      }
      if(layer.protectiveCloseObservedAt > 0 &&
         ctx.now > layer.protectiveCloseObservedAt + BD_ARCS_PROTECTIVE_WAIT_TIMEOUT_SEC)
      {
         why = "timeout waiting exact DEAL_ADD for observed protective close";
         LatchReconcile(dir, why);
         Save(why);
         return true;
      }
      // Intentional terminal hold for this tick: no Core DCA, no Gnext.
      return true;
   }

   bool ResumeAfterConsumedProtectiveClose(const eRecoveryCoreDirection dir,
                                           const EAContext &ctx,
                                           string &why)
   {
      int di = Idx(dir);
      if(m_dir[di].phase != ARCS_LOCKED || m_dir[di].activeLayer < 0)
         return false;
      int li = m_dir[di].activeLayer;
      SArcsLayer layer;
      GetLayer(dir, li, layer);
      if(!layer.used || layer.state != ARCS_LAYER_CLOSED ||
         layer.protectiveCloseObservedAt <= 0)
         return false;

      // DEAL proof has now been consumed and persisted. Only now may ARCS
      // advance to the next generation.
      layer.protectiveCloseObservedAt = 0;
      PutLayer(dir, li, layer);
      return AfterLayerLocked(dir, ctx.now, why);
   }

public:
   // T16.1 classifier: prefer durable layer target, but if event ordering has
   // already moved mutable state, exact ExecutionLayer MODIFY identity can
   // independently prove that this broker SL was Recovery-owned.
   bool ExpectedBrokerSlDeal(const ulong deal)
   {
      if(HedgeSLMode_ != SL_BROKER || deal == 0 || !HistoryDealSelect(deal)) return false;
      if(HistoryDealGetInteger(deal, DEAL_REASON) != DEAL_REASON_SL) return false;

      ulong positionId = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
      long dealType = HistoryDealGetInteger(deal, DEAL_TYPE);
      double programmedSl = HistoryDealGetDouble(deal, DEAL_SL);
      double dealPrice = HistoryDealGetDouble(deal, DEAL_PRICE);
      if(positionId == 0 || programmedSl <= 0.0 || dealPrice <= 0.0) return false;

      int generation = -1;
      ulong positionTicket = 0;
      if(!RecoveryPositionIdentity(positionId, generation, positionTicket)) return false;
      if(!HistoryDealSelect(deal)) return false;

      eRecoveryCoreDirection dir;
      if(!DealDirection(dealType, dir)) return false;
      int li = FindLayerByGeneration(dir, generation);
      double target = 0.0;
      if(li >= 0)
      {
         SArcsLayer layer;
         GetLayer(dir, li, layer);
         target = m_dir[Idx(dir)].globalSlArmed && m_dir[Idx(dir)].globalSlPrice > 0.0
                  ? m_dir[Idx(dir)].globalSlPrice
                  : layer.lockTargetPrice;
      }

      double slTolerance = MathMax(2.0 * m_tickSize, _Point);
      double spreadPrice = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point;
      double fillTolerance = MathMax(25.0 * m_tickSize,
                                     2.0 * spreadPrice + 2.0 * m_tickSize);
      bool modifyProof = false;
      if(positionTicket != 0)
         modifyProof = Exec_T14ModifyProofMatches(positionTicket,
                                                  (long)RecoveryMagic_,
                                                  Recovery_CycleKey(dir),
                                                  programmedSl,
                                                  slTolerance);
      // Hedging brokers commonly keep opening order ticket == position id,
      // but use this only as a second exact-key attempt, never as sole proof.
      if(!modifyProof)
         modifyProof = Exec_T14ModifyProofMatches(positionId,
                                                  (long)RecoveryMagic_,
                                                  Recovery_CycleKey(dir),
                                                  programmedSl,
                                                  slTolerance);

      // If mutable layer state is unavailable/moved, a confirmed exact MODIFY
      // proof promotes the deal's own programmed SL to the durable target.
      if(target <= 0.0 || MathAbs(target - programmedSl) > slTolerance)
      {
         if(!modifyProof) return false;
         target = programmedSl;
      }

      return Recovery_ProtectiveSlIdentityPure(true,
                                               generation >= 1,
                                               DEAL_REASON_SL,
                                               programmedSl,
                                               target,
                                               dealPrice,
                                               slTolerance,
                                               fillTolerance,
                                               modifyProof);
   }

   bool StartupReconcile(CExecutionLayer &exec, string &why)
   {
      why = "";
      if(RecoveryMode_ == recovery_ACTIVE && m_initialized &&
         m_persistLoaded && !m_persistenceBlocked)
      {
         string repairWhy = "";
         if(!RepairProtectiveLayerDecreases(recovery_CORE_BUY, repairWhy) ||
            !RepairProtectiveLayerDecreases(recovery_CORE_SELL, repairWhy))
         {
            why = repairWhy;
            m_ready = false;
            return false;
         }
      }
      return CRecoveryArcsStackBase::StartupReconcile(exec, why);
   }

   void OnTradeTransaction(const MqlTradeTransaction &trans)
   {
      CRecoveryArcsStackBase::OnTradeTransaction(trans);
      if(!m_initialized || RecoveryMode_ != recovery_ACTIVE ||
         trans.type != TRADE_TRANSACTION_DEAL_ADD || trans.deal == 0 ||
         trans.symbol != _Symbol)
         return;
      RefreshClosedGenerationFromDeal(trans);
      string why = "";
      if(m_dirty && !Save(why))
         Log_Error("Recovery", "T16.1 protective-layer persistence failed: " + why);
   }

   void OnTick(const EAContext &ctx)
   {
      if(!m_initialized || RecoveryMode_ == recovery_OFF) return;
      for(int d = 0; d < 2; d++)
      {
         eRecoveryCoreDirection dir = d == 0 ? recovery_CORE_BUY : recovery_CORE_SELL;
         long core = Recovery_ArcsCoreUnits(dir, m_volumeStep);
         long hedge = Recovery_ArcsTotalHedgeUnits(dir, m_volumeStep);
         m_dir[d].lastObservedCoreUnits = core;
         m_dir[d].lastObservedHedgeUnits = hedge;
         if(core <= 0 && hedge <= 0 && m_dir[d].phase == ARCS_REVERSAL_HOLD)
            ResetDirection(dir);
         if(m_dir[d].phase == ARCS_IDLE) ArmFromCore(dir, ctx.now);
         if(RecoveryMode_ == recovery_SHADOW && m_dir[d].phase == ARCS_ARMED && InitialGapHit(dir, ctx))
         {
            long target = Recovery_T16NewGenerationUnitsPure(RecoverySizingPolicy_, core, hedge,
                                                             HedgeVolumePercent_);
            Log_Info("Recovery", "T16 SHADOW " + Recovery_DirectionName(dir) +
                     " would open G1=" + DoubleToString(Recovery_UnitsToVolume(target, m_volumeStep), 2) +
                     " lot at HedgeVolume=" + DoubleToString(HedgeVolumePercent_, 2) + "%");
            m_dir[d].phase = ARCS_ACTIVE;
         }
      }
   }

   bool Drive(CExecutionLayer &exec, const EAContext &ctx, string &why)
   {
      why = "";
      NormalizeStableLockedHold(recovery_CORE_BUY);
      NormalizeStableLockedHold(recovery_CORE_SELL);

      if(EnterProtectiveCloseWait(recovery_CORE_BUY, ctx, why) ||
         HoldProtectiveCloseWait(recovery_CORE_BUY, ctx, why) ||
         ResumeAfterConsumedProtectiveClose(recovery_CORE_BUY, ctx, why))
         return true;
      if(EnterProtectiveCloseWait(recovery_CORE_SELL, ctx, why) ||
         HoldProtectiveCloseWait(recovery_CORE_SELL, ctx, why) ||
         ResumeAfterConsumedProtectiveClose(recovery_CORE_SELL, ctx, why))
         return true;

      bool terminal = CRecoveryArcsStackBase::Drive(exec, ctx, why);
      if(!terminal && why == "TP Hedge ảo chưa đạt") why = "";
      return terminal;
   }
};

#endif // BD_RECOVERY_ARCS_STACK_HARDENED_MQH
