//+------------------------------------------------------------------+
//| RecoveryArcsStackT177HedgeLadder.mqh — T17.8 runtime wrapper    |
//| Keeps verified C4 Hedge ladder byte-identical in C4Base.         |
//| Fix A: ACTIVE/no-TP is read-only and yields DCA/Pyramid.         |
//| Fix A2: persistence-only bookkeeping never owns Strategy tick.  |
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_ARCS_STACK_T178_RUNTIME_WRAPPER_MQH
#define BD_RECOVERY_ARCS_STACK_T178_RUNTIME_WRAPPER_MQH

#include "RecoveryArcsStackT177HedgeLadderC4Base.mqh"
#include "RecoveryT178RuntimePolicy.mqh"

struct SRecoveryT178SemanticSnapshot
{
   eArcsPhase      phase0;
   eArcsPhase      phase1;
   int             generation0;
   int             generation1;
   int             activeLayer0;
   int             activeLayer1;
   eArcsLayerState layerState0;
   eArcsLayerState layerState1;
   long            layerTarget0;
   long            layerTarget1;
   long            layerOpened0;
   long            layerOpened1;
   long            layerRemaining0;
   long            layerRemaining1;
   long            coreUnits0;
   long            coreUnits1;
   long            hedgeUnits0;
   long            hedgeUnits1;
   bool            armed0;
   bool            armed1;
   long            anchorTicks0;
   long            anchorTicks1;
   double          credit0;
   double          credit1;
   bool            globalArmed0;
   bool            globalArmed1;
   double          globalPrice0;
   double          globalPrice1;
   double          transition0;
   double          transition1;
   bool            externalPending0;
   bool            externalPending1;
   bool            reconcile0;
   bool            reconcile1;
   uint            brokerFingerprint;
};

class CRecoveryArcsStackT178 : public CRecoveryArcsStackT177C4
{
private:
   int T178Idx(const eRecoveryCoreDirection dir) const
   {
      return dir == recovery_CORE_BUY ? 0 : 1;
   }

   uint BrokerFingerprintT178() const
   {
      string canonical = "";
      int total = PositionsTotal();
      for(int i = 0; i < total; i++)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         long magic = PositionGetInteger(POSITION_MAGIC);
         if(magic != (long)Magic && magic != (long)RecoveryMagic_) continue;
         canonical += (string)ticket + "|" +
                      (string)magic + "|" +
                      (string)PositionGetInteger(POSITION_TYPE) + "|" +
                      DoubleToString(PositionGetDouble(POSITION_VOLUME), 8) + "|" +
                      DoubleToString(PositionGetDouble(POSITION_PRICE_OPEN), 8) + "|" +
                      DoubleToString(PositionGetDouble(POSITION_SL), 8) + "|" +
                      DoubleToString(PositionGetDouble(POSITION_TP), 8) + ";";
      }
      return Recovery_Fnv1aTextPure(canonical);
   }

   void CaptureSemanticT178(SRecoveryT178SemanticSnapshot &out) const
   {
      ZeroMemory(out);
      out.phase0 = m_dir[0].phase;
      out.phase1 = m_dir[1].phase;
      out.generation0 = m_dir[0].generationCount;
      out.generation1 = m_dir[1].generationCount;
      out.activeLayer0 = m_dir[0].activeLayer;
      out.activeLayer1 = m_dir[1].activeLayer;
      out.armed0 = m_dir[0].armed;
      out.armed1 = m_dir[1].armed;
      out.anchorTicks0 = m_dir[0].anchorTicks;
      out.anchorTicks1 = m_dir[1].anchorTicks;
      out.credit0 = m_dir[0].availableCredit;
      out.credit1 = m_dir[1].availableCredit;
      out.globalArmed0 = m_dir[0].globalSlArmed;
      out.globalArmed1 = m_dir[1].globalSlArmed;
      out.globalPrice0 = m_dir[0].globalSlPrice;
      out.globalPrice1 = m_dir[1].globalSlPrice;
      out.transition0 = m_dir[0].transitionReferencePrice;
      out.transition1 = m_dir[1].transitionReferencePrice;
      out.externalPending0 = m_pending[0].active;
      out.externalPending1 = m_pending[1].active;
      out.reconcile0 = m_dir[0].reconcileRequired;
      out.reconcile1 = m_dir[1].reconcileRequired;

      SArcsLayer layer;
      Recovery_ArcsLayerReset(layer);
      if(out.activeLayer0 >= 0)
         GetLayer(recovery_CORE_BUY, out.activeLayer0, layer);
      out.layerState0 = layer.state;
      out.layerTarget0 = layer.targetUnits;
      out.layerOpened0 = layer.openedUnits;
      out.layerRemaining0 = layer.remainingUnits;

      Recovery_ArcsLayerReset(layer);
      if(out.activeLayer1 >= 0)
         GetLayer(recovery_CORE_SELL, out.activeLayer1, layer);
      out.layerState1 = layer.state;
      out.layerTarget1 = layer.targetUnits;
      out.layerOpened1 = layer.openedUnits;
      out.layerRemaining1 = layer.remainingUnits;

      out.coreUnits0 = Recovery_ArcsCoreUnits(recovery_CORE_BUY, m_volumeStep);
      out.coreUnits1 = Recovery_ArcsCoreUnits(recovery_CORE_SELL, m_volumeStep);
      out.hedgeUnits0 = Recovery_ArcsTotalHedgeUnits(recovery_CORE_BUY, m_volumeStep);
      out.hedgeUnits1 = Recovery_ArcsTotalHedgeUnits(recovery_CORE_SELL, m_volumeStep);
      out.brokerFingerprint = BrokerFingerprintT178();
   }

   bool SameSemanticT178(const SRecoveryT178SemanticSnapshot &a,
                         const SRecoveryT178SemanticSnapshot &b) const
   {
      return a.phase0 == b.phase0 && a.phase1 == b.phase1 &&
             a.generation0 == b.generation0 && a.generation1 == b.generation1 &&
             a.activeLayer0 == b.activeLayer0 && a.activeLayer1 == b.activeLayer1 &&
             a.layerState0 == b.layerState0 && a.layerState1 == b.layerState1 &&
             a.layerTarget0 == b.layerTarget0 && a.layerTarget1 == b.layerTarget1 &&
             a.layerOpened0 == b.layerOpened0 && a.layerOpened1 == b.layerOpened1 &&
             a.layerRemaining0 == b.layerRemaining0 && a.layerRemaining1 == b.layerRemaining1 &&
             a.coreUnits0 == b.coreUnits0 && a.coreUnits1 == b.coreUnits1 &&
             a.hedgeUnits0 == b.hedgeUnits0 && a.hedgeUnits1 == b.hedgeUnits1 &&
             a.armed0 == b.armed0 && a.armed1 == b.armed1 &&
             a.anchorTicks0 == b.anchorTicks0 && a.anchorTicks1 == b.anchorTicks1 &&
             MathAbs(a.credit0 - b.credit0) <= 1e-9 &&
             MathAbs(a.credit1 - b.credit1) <= 1e-9 &&
             a.globalArmed0 == b.globalArmed0 && a.globalArmed1 == b.globalArmed1 &&
             MathAbs(a.globalPrice0 - b.globalPrice0) <= 1e-12 &&
             MathAbs(a.globalPrice1 - b.globalPrice1) <= 1e-12 &&
             MathAbs(a.transition0 - b.transition0) <= 1e-12 &&
             MathAbs(a.transition1 - b.transition1) <= 1e-12 &&
             a.externalPending0 == b.externalPending0 &&
             a.externalPending1 == b.externalPending1 &&
             a.reconcile0 == b.reconcile0 && a.reconcile1 == b.reconcile1 &&
             a.brokerFingerprint == b.brokerFingerprint;
   }

   bool TryYieldStableActiveTpWaitT178(const eRecoveryCoreDirection dir,
                                       const EAContext &ctx,
                                       string &why)
   {
      why = "";
      int di = T178Idx(dir);
      if(m_dir[di].phase != ARCS_ACTIVE || m_dir[di].activeLayer < 0)
         return false;

      int li = m_dir[di].activeLayer;
      SArcsLayer layer;
      GetLayer(dir, li, layer);
      if(!layer.used || layer.state != ARCS_LAYER_ACTIVE)
         return false;

      SArcsPosition pos[];
      SArcsLayerSnapshot snap;
      string snapWhy = "";
      if(!Recovery_ArcsLayerSnapshot(dir, layer.generation,
                                     m_volumeStep, m_tickSize,
                                     pos, snap, snapWhy))
         return false; // let verified base classify/reconcile the bad snapshot

      bool tpHit = Recovery_VirtualHedgeTpHit(dir, snap.netBE,
                                              ctx.bid, ctx.ask,
                                              m_tpDistancePrice);
      if(!Recovery_T178ActiveTpWaitNoMutationPure(true, true,
                                                   snap.units,
                                                   layer.openedUnits,
                                                   layer.remainingUnits,
                                                   tpHit))
         return false;

      Log_WarnEvery("Recovery",
                    "t178activewait" + (string)Recovery_CycleKey(dir),
                    "CHỜ " + Recovery_DirectionName(dir) +
                    " | Hedge đã đủ target, TP chưa đạt | DCA/Pyramid tiếp tục được xét",
                    Recovery_T165WaitLogSecondsPure(RecoveryWaitLogSeconds_));
      return true;
   }

public:
   CRecoveryArcsStackT178(void) : CRecoveryArcsStackT177C4() {}

   bool Drive(CExecutionLayer &exec, const EAContext &ctx, string &why)
   {
      // P1-A primary fix: do not enter PrepareTp() for the steady ACTIVE/no-TP
      // case. That path used to PutLayer()+FlushPersistence on every tick.
      if(TryYieldStableActiveTpWaitT178(recovery_CORE_BUY, ctx, why)) return false;
      if(TryYieldStableActiveTpWaitT178(recovery_CORE_SELL, ctx, why)) return false;

      SRecoveryT178SemanticSnapshot before;
      CaptureSemanticT178(before);
      bool consumed = CRecoveryArcsStackT177C4::Drive(exec, ctx, why);
      SRecoveryT178SemanticSnapshot after;
      CaptureSemanticT178(after);

      bool pending = exec.HasPendingForCycle(Recovery_CycleKey(recovery_CORE_BUY)) ||
                     exec.HasPendingForCycle(Recovery_CycleKey(recovery_CORE_SELL));
      bool reconcile = !m_ready ||
                       m_dir[0].phase == ARCS_RECONCILE ||
                       m_dir[1].phase == ARCS_RECONCILE ||
                       m_dir[0].reconcileRequired ||
                       m_dir[1].reconcileRequired ||
                       exec.HasReconcileRequired(Recovery_CycleKey(recovery_CORE_BUY)) ||
                       exec.HasReconcileRequired(Recovery_CycleKey(recovery_CORE_SELL));
      bool semanticChanged = !SameSemanticT178(before, after);

      if(Recovery_T178PersistenceOnlyYieldPure(consumed, semanticChanged,
                                               pending, reconcile))
      {
         Log_WarnEvery("Recovery", "t178persistyield",
                       "CHỜ | Recovery chỉ cập nhật sổ trạng thái, không có thay đổi lệnh | DCA/Pyramid tiếp tục được xét",
                       Recovery_T165WaitLogSecondsPure(RecoveryWaitLogSeconds_));
         why = "";
         return false;
      }
      return consumed;
   }
};

// RecoveryEngine.mqh still contains the historical type token so all existing
// source gates remain meaningful, but after this include it resolves to T17.8.
#define CRecoveryArcsStackT177C4 CRecoveryArcsStackT178

#endif // BD_RECOVERY_ARCS_STACK_T178_RUNTIME_WRAPPER_MQH
