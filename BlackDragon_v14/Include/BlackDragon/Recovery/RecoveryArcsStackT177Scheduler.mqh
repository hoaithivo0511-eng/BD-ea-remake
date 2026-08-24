//+------------------------------------------------------------------+
//| RecoveryArcsStackT177Scheduler.mqh — T17.7 C1 side-aware yield  |
//| Wraps T17.6 without changing its Recovery state machine.         |
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_ARCS_STACK_T177_SCHEDULER_MQH
#define BD_RECOVERY_ARCS_STACK_T177_SCHEDULER_MQH

#include "RecoveryT177Scheduler.mqh"

// Preserve the verified T17.6 implementation as the base, then add only the
// scheduler contract on top. Existing state/persistence/trade semantics remain
// byte-for-byte in RecoveryArcsStackT17Pyramid.mqh.
#define CRecoveryArcsStackT17 CRecoveryArcsStackT176Base
#include "RecoveryArcsStackT17Pyramid.mqh"
#undef CRecoveryArcsStackT17

struct SRecoveryT177DriveSnapshot
{
   eArcsPhase      buyPhase;
   eArcsPhase      sellPhase;
   int             buyGeneration;
   int             sellGeneration;
   int             buyActiveLayer;
   int             sellActiveLayer;
   eArcsLayerState buyLayerState;
   eArcsLayerState sellLayerState;
   long            buyLayerTarget;
   long            sellLayerTarget;
   long            buyLayerOpened;
   long            sellLayerOpened;
   long            buyLayerRemaining;
   long            sellLayerRemaining;
   long            buyCoreUnits;
   long            sellCoreUnits;
   long            buyHedgeUnits;
   long            sellHedgeUnits;
   bool            buyArmed;
   bool            sellArmed;
   long            buyAnchorTicks;
   long            sellAnchorTicks;
   double          buyCredit;
   double          sellCredit;
   bool            buyGlobalSlArmed;
   bool            sellGlobalSlArmed;
   double          buyGlobalSlPrice;
   double          sellGlobalSlPrice;
   double          buyTransitionPrice;
   double          sellTransitionPrice;
   bool            buyExternalPending;
   bool            sellExternalPending;
   bool            buyReconcile;
   bool            sellReconcile;
   long            saveSequence;
   uint            brokerFingerprint;
};

class CRecoveryArcsStackT17 : public CRecoveryArcsStackT176Base
{
private:
   uint BrokerFingerprint() const
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

   void Capture(SRecoveryT177DriveSnapshot &out) const
   {
      ZeroMemory(out);
      out.buyPhase = m_dir[0].phase;
      out.sellPhase = m_dir[1].phase;
      out.buyGeneration = m_dir[0].generationCount;
      out.sellGeneration = m_dir[1].generationCount;
      out.buyActiveLayer = m_dir[0].activeLayer;
      out.sellActiveLayer = m_dir[1].activeLayer;
      out.buyArmed = m_dir[0].armed;
      out.sellArmed = m_dir[1].armed;
      out.buyAnchorTicks = m_dir[0].anchorTicks;
      out.sellAnchorTicks = m_dir[1].anchorTicks;
      out.buyCredit = m_dir[0].availableCredit;
      out.sellCredit = m_dir[1].availableCredit;
      out.buyGlobalSlArmed = m_dir[0].globalSlArmed;
      out.sellGlobalSlArmed = m_dir[1].globalSlArmed;
      out.buyGlobalSlPrice = m_dir[0].globalSlPrice;
      out.sellGlobalSlPrice = m_dir[1].globalSlPrice;
      out.buyTransitionPrice = m_dir[0].transitionReferencePrice;
      out.sellTransitionPrice = m_dir[1].transitionReferencePrice;
      out.buyExternalPending = m_pending[0].active;
      out.sellExternalPending = m_pending[1].active;
      out.buyReconcile = m_dir[0].reconcileRequired;
      out.sellReconcile = m_dir[1].reconcileRequired;
      out.saveSequence = m_saveSequence;

      SArcsLayer layer;
      Recovery_ArcsLayerReset(layer);
      if(out.buyActiveLayer >= 0)
         GetLayer(recovery_CORE_BUY, out.buyActiveLayer, layer);
      out.buyLayerState = layer.state;
      out.buyLayerTarget = layer.targetUnits;
      out.buyLayerOpened = layer.openedUnits;
      out.buyLayerRemaining = layer.remainingUnits;

      Recovery_ArcsLayerReset(layer);
      if(out.sellActiveLayer >= 0)
         GetLayer(recovery_CORE_SELL, out.sellActiveLayer, layer);
      out.sellLayerState = layer.state;
      out.sellLayerTarget = layer.targetUnits;
      out.sellLayerOpened = layer.openedUnits;
      out.sellLayerRemaining = layer.remainingUnits;

      out.buyCoreUnits = Recovery_ArcsCoreUnits(recovery_CORE_BUY, m_volumeStep);
      out.sellCoreUnits = Recovery_ArcsCoreUnits(recovery_CORE_SELL, m_volumeStep);
      out.buyHedgeUnits = Recovery_ArcsTotalHedgeUnits(recovery_CORE_BUY, m_volumeStep);
      out.sellHedgeUnits = Recovery_ArcsTotalHedgeUnits(recovery_CORE_SELL, m_volumeStep);
      out.brokerFingerprint = BrokerFingerprint();
   }

   bool SameSnapshot(const SRecoveryT177DriveSnapshot &a,
                     const SRecoveryT177DriveSnapshot &b) const
   {
      return a.buyPhase == b.buyPhase &&
             a.sellPhase == b.sellPhase &&
             a.buyGeneration == b.buyGeneration &&
             a.sellGeneration == b.sellGeneration &&
             a.buyActiveLayer == b.buyActiveLayer &&
             a.sellActiveLayer == b.sellActiveLayer &&
             a.buyLayerState == b.buyLayerState &&
             a.sellLayerState == b.sellLayerState &&
             a.buyLayerTarget == b.buyLayerTarget &&
             a.sellLayerTarget == b.sellLayerTarget &&
             a.buyLayerOpened == b.buyLayerOpened &&
             a.sellLayerOpened == b.sellLayerOpened &&
             a.buyLayerRemaining == b.buyLayerRemaining &&
             a.sellLayerRemaining == b.sellLayerRemaining &&
             a.buyCoreUnits == b.buyCoreUnits &&
             a.sellCoreUnits == b.sellCoreUnits &&
             a.buyHedgeUnits == b.buyHedgeUnits &&
             a.sellHedgeUnits == b.sellHedgeUnits &&
             a.buyArmed == b.buyArmed &&
             a.sellArmed == b.sellArmed &&
             a.buyAnchorTicks == b.buyAnchorTicks &&
             a.sellAnchorTicks == b.sellAnchorTicks &&
             MathAbs(a.buyCredit - b.buyCredit) <= 1e-9 &&
             MathAbs(a.sellCredit - b.sellCredit) <= 1e-9 &&
             a.buyGlobalSlArmed == b.buyGlobalSlArmed &&
             a.sellGlobalSlArmed == b.sellGlobalSlArmed &&
             MathAbs(a.buyGlobalSlPrice - b.buyGlobalSlPrice) <= 1e-12 &&
             MathAbs(a.sellGlobalSlPrice - b.sellGlobalSlPrice) <= 1e-12 &&
             MathAbs(a.buyTransitionPrice - b.buyTransitionPrice) <= 1e-12 &&
             MathAbs(a.sellTransitionPrice - b.sellTransitionPrice) <= 1e-12 &&
             a.buyExternalPending == b.buyExternalPending &&
             a.sellExternalPending == b.sellExternalPending &&
             a.buyReconcile == b.buyReconcile &&
             a.sellReconcile == b.sellReconcile &&
             a.saveSequence == b.saveSequence &&
             a.brokerFingerprint == b.brokerFingerprint;
   }

   int WaitDirectionIndex() const
   {
      if(m_dir[0].phase == ARCS_BUILDING) return 0;
      if(m_dir[1].phase == ARCS_BUILDING) return 1;
      if(m_dir[0].phase == ARCS_LOCK_PENDING ||
         m_dir[0].phase == ARCS_GLOBAL_PROTECT ||
         m_dir[0].phase == ARCS_TRANSITION) return 0;
      if(m_dir[1].phase == ARCS_LOCK_PENDING ||
         m_dir[1].phase == ARCS_GLOBAL_PROTECT ||
         m_dir[1].phase == ARCS_TRANSITION) return 1;
      if(m_dir[0].phase != ARCS_IDLE && m_dir[0].phase != ARCS_REVERSAL_HOLD) return 0;
      if(m_dir[1].phase != ARCS_IDLE && m_dir[1].phase != ARCS_REVERSAL_HOLD) return 1;
      return -1;
   }

   string WaitStateVi(const eArcsPhase phase) const
   {
      switch(phase)
      {
         case ARCS_BUILDING:       return "Hedge đang chờ điều kiện mở thêm";
         case ARCS_ACTIVE:         return "Hedge đang chờ mục tiêu chốt";
         case ARCS_TP_PENDING:     return "Hedge đang chờ xác nhận chốt";
         case ARCS_CORE_FUNDING:   return "Recovery đang chờ xử lý Core";
         case ARCS_LOCK_PENDING:   return "Hedge đang chờ khóa lợi nhuận";
         case ARCS_GLOBAL_PROTECT: return "Hedge đang chờ điều kiện bảo vệ";
         case ARCS_TRANSITION:     return "Recovery đang chờ giá chuyển pha";
         default:                  return "Recovery đang chờ điều kiện tiếp theo";
      }
   }

   void LogYieldWait() const
   {
      int di = WaitDirectionIndex();
      string side = di == 0 ? "BUY" : di == 1 ? "SELL" : "HAI PHÍA";
      eArcsPhase phase = di == 1 ? m_dir[1].phase : m_dir[0].phase;
      int key = di == 1 ? Recovery_CycleKey(recovery_CORE_SELL)
                        : Recovery_CycleKey(recovery_CORE_BUY);
      Log_WarnEvery("Recovery",
                    "t177yield" + (string)key,
                    "CHỜ " + side + " | " + WaitStateVi(phase) +
                    " | không khóa Pyramid phía đối diện",
                    Recovery_T165WaitLogSecondsPure(RecoveryWaitLogSeconds_));
   }

public:
   CRecoveryArcsStackT17(void) : CRecoveryArcsStackT176Base() {}

   bool Drive(CExecutionLayer &exec, const EAContext &ctx, string &why)
   {
      SRecoveryT177DriveSnapshot before;
      Capture(before);

      bool legacyConsumed = CRecoveryArcsStackT176Base::Drive(exec, ctx, why);

      SRecoveryT177DriveSnapshot after;
      Capture(after);

      bool pending = exec.HasPendingForCycle(Recovery_CycleKey(recovery_CORE_BUY)) ||
                     exec.HasPendingForCycle(Recovery_CycleKey(recovery_CORE_SELL));
      bool reconcile = !m_ready ||
                       m_dir[0].phase == ARCS_RECONCILE ||
                       m_dir[1].phase == ARCS_RECONCILE ||
                       m_dir[0].reconcileRequired ||
                       m_dir[1].reconcileRequired ||
                       exec.HasReconcileRequired(Recovery_CycleKey(recovery_CORE_BUY)) ||
                       exec.HasReconcileRequired(Recovery_CycleKey(recovery_CORE_SELL));
      bool semanticChanged = !SameSnapshot(before, after);

      eRecoveryDriveDisposition d =
         Recovery_T177ClassifyDrivePure(legacyConsumed,
                                        semanticChanged,
                                        pending,
                                        reconcile);

      if(d == RECOVERY_DRIVE_WAIT)
      {
         LogYieldWait();
         why = "";
      }
      else if(d == RECOVERY_DRIVE_RECONCILE && why == "")
         why = "Recovery cần đối soát trước khi tiếp tục";

      return Recovery_T177ConsumesStrategyTickPure(d);
   }
};

#endif // BD_RECOVERY_ARCS_STACK_T177_SCHEDULER_MQH
