//+------------------------------------------------------------------+
//| RecoveryArcsStackPostDeal.mqh — T16.3 liveness compatibility     |
//| Keeps the exact T16.2 post-deal implementation as a pinned base. |
//| Adds scheduling-only liveness views without weakening safety.    |
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_ARCS_STACK_T163_WRAPPER_MQH
#define BD_RECOVERY_ARCS_STACK_T163_WRAPPER_MQH

// Pin the exact T16.2 implementation and expose its internals only to this
// derived liveness layer. This mirrors the existing T14/T16 wrapper pattern.
#define private protected
#define CRecoveryArcsStackFinal CRecoveryArcsStackT162Base
#include "RecoveryArcsStackPostDealT162Base.mqh"
#undef CRecoveryArcsStackFinal
#undef private

class CRecoveryArcsStackFinal : public CRecoveryArcsStackT162Base
{
private:
   bool m_dcaYield[2];
   bool m_maxedLogged[2];

   bool DeterministicLockWaitWhy(const string why) const
   {
      return StringFind(why, "SL dương chưa đặt được theo fresh stops/freeze broker; giữ LOCK_PENDING") >= 0 ||
             StringFind(why, "broker từ chối SL generation nhưng outcome xác định không có mutation; retry tick mới") >= 0;
   }

   bool MaxedNoHedge(const eRecoveryCoreDirection dir) const
   {
      int di = Idx(dir);
      eArcsPhase p = m_dir[di].phase;
      if(p != ARCS_LOCKED && p != ARCS_REVERSAL_HOLD) return false;
      if(m_dir[di].generationCount < MaxHedgeGenerations_) return false;
      long core = Recovery_ArcsCoreUnits(dir, m_volumeStep);
      long hedge = Recovery_ArcsTotalHedgeUnits(dir, m_volumeStep);
      return core > 0 && hedge <= 0;
   }

   void UpdateMaxedTelemetry(const eRecoveryCoreDirection dir)
   {
      int di = Idx(dir);
      bool active = MaxedNoHedge(dir);
      if(active && !m_maxedLogged[di])
      {
         long core = Recovery_ArcsCoreUnits(dir, m_volumeStep);
         Log_Warn("Recovery", "t163maxed" + (string)Recovery_CycleKey(dir),
                  "T16.3 MAXED_NO_HEDGE: đã đạt MaxHedgeGenerations=" +
                  (string)MaxHedgeGenerations_ +
                  ", Hedge=0 nhưng Core còn " +
                  DoubleToString(Recovery_UnitsToVolume(core, m_volumeStep), 2) +
                  " lot; cấm generation mới nhưng cho phép Core DCA/Overlap ổn định theo cấu hình");
         m_maxedLogged[di] = true;
      }
      else if(!active)
         m_maxedLogged[di] = false;
   }

   int DeterministicDeferredDirection(CExecutionLayer &exec) const
   {
      // Base Drive always evaluates BUY_CORE before SELL_CORE. If it returns a
      // deterministic lock-wait reason, the first eligible LOCK_PENDING cycle
      // is therefore the cycle that yielded this tick.
      int buyKey = Recovery_CycleKey(recovery_CORE_BUY);
      if(m_dir[0].phase == ARCS_LOCK_PENDING &&
         !exec.HasPendingForCycle(buyKey) && !exec.HasReconcileRequired(buyKey))
         return 0;

      int sellKey = Recovery_CycleKey(recovery_CORE_SELL);
      if(m_dir[1].phase == ARCS_LOCK_PENDING &&
         !exec.HasPendingForCycle(sellKey) && !exec.HasReconcileRequired(sellKey))
         return 1;
      return -1;
   }

public:
   CRecoveryArcsStackFinal(void) : CRecoveryArcsStackT162Base()
   {
      m_dcaYield[0] = false;
      m_dcaYield[1] = false;
      m_maxedLogged[0] = false;
      m_maxedLogged[1] = false;
   }

   bool Drive(CExecutionLayer &exec, const EAContext &ctx, string &why)
   {
      // Scheduling yield is intentionally ephemeral: it is recomputed from a
      // fresh broker preflight every tick and is never trusted across restart.
      m_dcaYield[0] = false;
      m_dcaYield[1] = false;

      bool consumed = CRecoveryArcsStackT162Base::Drive(exec, ctx, why);

      // T16.2 correctly keeps the retained layer in LOCK_PENDING when the
      // positive SL cannot yet be placed, but returning true starved all Core
      // work for hours. If there is NO pending command and NO ambiguous result,
      // this is a deterministic local wait rather than an unresolved mutation.
      // Yield the remainder of this tick to legacy Core DCA only. The next tick
      // retries the lock first, and any actual/ambiguous broker command remains
      // terminal for the tick exactly as before.
      if(consumed && DeterministicLockWaitWhy(why))
      {
         int di = DeterministicDeferredDirection(exec);
         if(di >= 0)
         {
            m_dcaYield[di] = true;
            eRecoveryCoreDirection dir = di == 0 ? recovery_CORE_BUY : recovery_CORE_SELL;
            Log_Warn("Recovery", "t163lockyield" + (string)Recovery_CycleKey(dir),
                     "T16.3 deferred-lock yield: retained Hedge vẫn chờ khóa, execution journal quiet; Core DCA được phép tiếp tục nếu ContinueDcaAfterHedge=true");
            consumed = false;
         }
      }

      UpdateMaxedTelemetry(recovery_CORE_BUY);
      UpdateMaxedTelemetry(recovery_CORE_SELL);
      return consumed;
   }

   // SRecoveryCycle is the compatibility/scheduling view used by T7/T8. Keep
   // the internal ARCS phase untouched and expose only the safe scheduling
   // equivalent needed by existing policy functions:
   // - deferred lock => REHEDGE_PENDING: T7 permits DCA, T8 Overlap still defers;
   // - maxed/no-Hedge => HEDGE_LOCKED: stable Core management is allowed, but
   //   StartGeneration remains blocked by generationCount >= Max.
   void GetCycle(const eRecoveryCoreDirection dir, SRecoveryCycle &out) const
   {
      CRecoveryArcsStackT162Base::GetCycle(dir, out);
      int di = Idx(dir);
      if(m_dcaYield[di])
      {
         out.state = recovery_REHEDGE_PENDING;
         return;
      }
      if(MaxedNoHedge(dir))
         out.state = recovery_HEDGE_LOCKED;
   }
};

#endif // BD_RECOVERY_ARCS_STACK_T163_WRAPPER_MQH
