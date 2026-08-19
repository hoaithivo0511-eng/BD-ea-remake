//+------------------------------------------------------------------+
//| RecoveryArcsStackHardened.mqh — T16 restart/SL hardening wrapper |
//| Keeps the core stacked engine readable while independently       |
//| enforcing monotonic layer ownership across protective closes.    |
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_ARCS_STACK_HARDENED_MQH
#define BD_RECOVERY_ARCS_STACK_HARDENED_MQH

// Expose T16 implementation internals only to this compatibility hardening
// layer. The source class is renamed exactly like the T14/T15 wrappers.
#define private protected
#define CRecoveryArcsStack CRecoveryArcsStackBase
#include "RecoveryArcsStack.mqh"
#undef CRecoveryArcsStack
#undef private

struct SArcsHardeningCloseDeal
{
   ulong  deal;
   ulong  positionId;
   long   type;
   long   reason;
   double programmedSl;
   double volume;
};

class CRecoveryArcsStack : public CRecoveryArcsStackBase
{
private:
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

      // Virtual SL never exists at broker. Recovery-owned close requests use
      // DEAL_REASON_EXPERT. Persisted virtualSlArmed + generation ownership is
      // required; manual/mobile/random closes remain fail-closed.
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
            layer.state != ARCS_LAYER_GLOBAL_PROTECTED)
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
            long directMagic = HistoryDealGetInteger(deal, DEAL_MAGIC);
            ulong positionId = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
            long type = HistoryDealGetInteger(deal, DEAL_TYPE);
            long reason = HistoryDealGetInteger(deal, DEAL_REASON);
            double programmedSl = HistoryDealGetDouble(deal, DEAL_SL);
            double volume = HistoryDealGetDouble(deal, DEAL_VOLUME);

            long owner = directMagic;
            if(owner != (long)RecoveryMagic_ && positionId != 0 &&
               HistorySelectByPosition(positionId))
            {
               ulong oldest = 0;
               long oldestMsc = 0;
               for(int h = 0; h < HistoryDealsTotal(); h++)
               {
                  ulong od = HistoryDealGetTicket(h);
                  if(od == 0 || HistoryDealGetString(od, DEAL_SYMBOL) != _Symbol) continue;
                  long oe = HistoryDealGetInteger(od, DEAL_ENTRY);
                  if(oe != DEAL_ENTRY_IN && oe != DEAL_ENTRY_INOUT) continue;
                  long tm = HistoryDealGetInteger(od, DEAL_TIME_MSC);
                  if(oldest == 0 || tm < oldestMsc || (tm == oldestMsc && od < oldest))
                  {
                     oldest = od;
                     oldestMsc = tm;
                     owner = HistoryDealGetInteger(od, DEAL_MAGIC);
                  }
               }
            }
            if(owner != (long)RecoveryMagic_ || positionId == 0) continue;

            int generation = Recovery_ArcsGenerationFromPositionHistory(positionId);
            if(generation != layer.generation) continue;

            SArcsHardeningCloseDeal d;
            d.deal = deal;
            d.positionId = positionId;
            d.type = type;
            d.reason = reason;
            d.programmedSl = programmedSl;
            d.volume = volume;
            if(!IsExpectedPersistedProtectiveClose(dir, layer, d)) continue;
            provenClose += Recovery_VolumeToUnitsFloor(volume, m_volumeStep);
         }

         if(provenClose != observedClose)
         {
            why = "persisted locked/global layer giảm volume nhưng không có exact protective-close proof";
            return false;
         }

         layer.remainingUnits = live;
         if(live == 0)
         {
            layer.state = ARCS_LAYER_CLOSED;
            layer.virtualSlArmed = false;
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
      long directMagic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
      ulong positionId = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
      long type = HistoryDealGetInteger(trans.deal, DEAL_TYPE);
      if(positionId == 0) return;

      long owner = directMagic;
      if(owner != (long)RecoveryMagic_ && HistorySelectByPosition(positionId))
      {
         ulong oldest = 0;
         long oldestMsc = 0;
         for(int i = 0; i < HistoryDealsTotal(); i++)
         {
            ulong d = HistoryDealGetTicket(i);
            if(d == 0 || HistoryDealGetString(d, DEAL_SYMBOL) != _Symbol) continue;
            long e = HistoryDealGetInteger(d, DEAL_ENTRY);
            if(e != DEAL_ENTRY_IN && e != DEAL_ENTRY_INOUT) continue;
            long tm = HistoryDealGetInteger(d, DEAL_TIME_MSC);
            if(oldest == 0 || tm < oldestMsc || (tm == oldestMsc && d < oldest))
            {
               oldest = d;
               oldestMsc = tm;
               owner = HistoryDealGetInteger(d, DEAL_MAGIC);
            }
         }
      }
      if(owner != (long)RecoveryMagic_) return;

      eRecoveryCoreDirection dir;
      if(type == DEAL_TYPE_BUY) dir = recovery_CORE_BUY;
      else if(type == DEAL_TYPE_SELL) dir = recovery_CORE_SELL;
      else return;
      int generation = Recovery_ArcsGenerationFromPositionHistory(positionId);
      int li = FindLayerByGeneration(dir, generation);
      if(li < 0) return;
      SArcsLayer layer;
      GetLayer(dir, li, layer);

      // TP_PENDING is reconciled by its exact baseline/target/funding ledger.
      // Only retained/global layers are terminalized here.
      if(layer.state != ARCS_LAYER_LOCKED &&
         layer.state != ARCS_LAYER_GLOBAL_PROTECTED)
         return;

      long live = Recovery_ArcsLayerUnits(dir, generation, m_volumeStep);
      if(live < 0 || live > layer.remainingUnits)
      {
         LatchReconcile(dir, "post-deal layer volume violates persisted ownership");
         return;
      }
      layer.remainingUnits = live;
      if(live == 0)
      {
         layer.state = ARCS_LAYER_CLOSED;
         layer.virtualSlArmed = false;
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

public:
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
         Log_Error("Recovery", "T16 protective-layer persistence failed: " + why);
   }

   // Avoid a persistence write on every flat tick. The base implementation's
   // ResetDirection is needed when REVERSAL_HOLD becomes flat, but an already
   // clean IDLE direction has nothing to reset.
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
      NormalizeStableLockedHold(recovery_CORE_BUY);
      NormalizeStableLockedHold(recovery_CORE_SELL);
      bool terminal = CRecoveryArcsStackBase::Drive(exec, ctx, why);
      // Waiting for a virtual TP is normal state, not an operational warning.
      if(!terminal && why == "TP Hedge ảo chưa đạt") why = "";
      return terminal;
   }
};

#endif // BD_RECOVERY_ARCS_STACK_HARDENED_MQH
