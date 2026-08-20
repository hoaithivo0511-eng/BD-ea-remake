//+------------------------------------------------------------------+
//| RecoveryArcsStackPostDeal.mqh — T16.4 reachability/liveness      |
//| Keeps exact T16.2 mechanics + T16.3 scheduling hardening.        |
//| Adds reachability observability without changing trade semantics.|
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_ARCS_STACK_T164_WRAPPER_MQH
#define BD_RECOVERY_ARCS_STACK_T164_WRAPPER_MQH

#include "RecoveryT163Policy.mqh"
#include "RecoveryT164Reachability.mqh"

// Pin the exact T16.2 implementation. The T16.1 hardened base already exposes
// original ARCS internals as protected; no second `private` macro is required.
#define CRecoveryArcsStackFinal CRecoveryArcsStackT162Base
#include "RecoveryArcsStackPostDealT162Base.mqh"
#undef CRecoveryArcsStackFinal

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
      bool terminalPhase = p == ARCS_LOCKED || p == ARCS_REVERSAL_HOLD;
      long core = Recovery_ArcsCoreUnits(dir, m_volumeStep);
      long hedge = Recovery_ArcsTotalHedgeUnits(dir, m_volumeStep);
      return Recovery_T163MaxedNoHedgePure(m_dir[di].generationCount,
                                           MaxHedgeGenerations_,
                                           core, hedge,
                                           terminalPhase);
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

   void LogCoreSaturation(const eRecoveryCoreDirection dir,
                          const int maxOrders)
   {
      if(RecoveryMode_ != recovery_ACTIVE || maxOrders < 1) return;
      SArcsPosition core[];
      int count = Recovery_ArcsBuildCore(dir, m_volumeStep, core);
      if(count < maxOrders) return;

      int required = Recovery_T164RequiredCoreCountPure(RecoveryStartAfterDca_);
      bool reachable = Recovery_T164SideReachablePure(true, maxOrders,
                                                      RecoveryStartAfterDca_);
      int di = Idx(dir);
      Log_Warn("Recovery", "t164maxorders" + (string)Recovery_CycleKey(dir),
               "T16.4 Core DCA saturated: " + Recovery_DirectionName(dir) +
               " count=" + (string)count +
               " MaxOrders=" + (string)maxOrders +
               "; RecoveryStartAfterDca=" + (string)RecoveryStartAfterDca_ +
               " requiresCore=" + (string)required +
               "; thresholdReachable=" + (reachable ? "yes" : "NO") +
               "; ARCS phase=" + Recovery_ArcsPhaseName(m_dir[di].phase));
   }

public:
   CRecoveryArcsStackFinal(void) : CRecoveryArcsStackT162Base()
   {
      m_dcaYield[0] = false;
      m_dcaYield[1] = false;
      m_maxedLogged[0] = false;
      m_maxedLogged[1] = false;
   }

   bool Init()
   {
      if(!CRecoveryArcsStackT162Base::Init()) return false;

      // Warning only: current-open-count semantics are owner-approved. If
      // Overlap can start before the Recovery threshold, make the competition
      // visible but do not silently change to cumulative-DCA counting.
      if(RecoveryMode_ == recovery_ACTIVE &&
         Recovery_T164OverlapMayPreemptPure(Overlap,
                                            OverlapOrderNumber,
                                            RecoveryStartAfterDca_))
      {
         Log_Warn("Recovery", "t164overlapthreshold",
                  "T16.4 cấu hình cảnh báo: OverlapOrderNumber=" +
                  (string)OverlapOrderNumber +
                  " có thể tỉa Core trước ngưỡng Recovery cần " +
                  (string)Recovery_T164RequiredCoreCountPure(RecoveryStartAfterDca_) +
                  " lệnh Core đang mở; semantic hiện tại vẫn đếm current-open Core, không phải cumulative DCA");
      }
      return true;
   }

   void OnTick(const EAContext &ctx)
   {
      CRecoveryArcsStackT162Base::OnTick(ctx);
      LogCoreSaturation(recovery_CORE_BUY, MaxOrdersBuy);
      LogCoreSaturation(recovery_CORE_SELL, MaxOrdersSell);
   }

   bool Drive(CExecutionLayer &exec, const EAContext &ctx, string &why)
   {
      m_dcaYield[0] = false;
      m_dcaYield[1] = false;

      bool consumed = CRecoveryArcsStackT162Base::Drive(exec, ctx, why);

      if(consumed && DeterministicLockWaitWhy(why))
      {
         int di = DeterministicDeferredDirection(exec);
         if(di >= 0)
         {
            eRecoveryCoreDirection dir = di == 0 ? recovery_CORE_BUY : recovery_CORE_SELL;
            int key = Recovery_CycleKey(dir);
            bool canYield = Recovery_T163DeferredLockYieldPure(consumed,
                                                               true,
                                                               exec.HasPendingForCycle(key),
                                                               exec.HasReconcileRequired(key));
            if(canYield)
            {
               m_dcaYield[di] = true;
               Log_Warn("Recovery", "t163lockyield" + (string)Recovery_CycleKey(dir),
                        "T16.3 deferred-lock yield: retained Hedge vẫn chờ khóa, execution journal quiet; Core DCA được phép tiếp tục nếu ContinueDcaAfterHedge=true");
               consumed = false;
            }
         }
      }

      UpdateMaxedTelemetry(recovery_CORE_BUY);
      UpdateMaxedTelemetry(recovery_CORE_SELL);
      return consumed;
   }

   void GetCycle(const eRecoveryCoreDirection dir, SRecoveryCycle &out) const
   {
      CRecoveryArcsStackT162Base::GetCycle(dir, out);
      int di = Idx(dir);
      out.state = Recovery_T163SchedulingStatePure(out.state,
                                                   m_dcaYield[di],
                                                   MaxedNoHedge(dir));
   }
};

#endif // BD_RECOVERY_ARCS_STACK_T164_WRAPPER_MQH
