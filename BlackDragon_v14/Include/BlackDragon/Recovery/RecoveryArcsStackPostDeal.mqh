//+------------------------------------------------------------------+
//| RecoveryArcsStackPostDeal.mqh — T16.5 safety/liveness wrapper    |
//| Preserves T16.1-T16.4 semantics and adds deterministic capacity |
//| WAIT plus low-frequency waiting telemetry.                       |
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_ARCS_STACK_T165_WRAPPER_MQH
#define BD_RECOVERY_ARCS_STACK_T165_WRAPPER_MQH

#include "RecoveryT163Policy.mqh"
#include "RecoveryT164Reachability.mqh"
#include "RecoveryT165Policy.mqh"

#define CRecoveryArcsStackFinal CRecoveryArcsStackT162Base
#include "RecoveryArcsStackPostDealT162Base.mqh"
#undef CRecoveryArcsStackFinal

class CRecoveryArcsStackFinal : public CRecoveryArcsStackT162Base
{
private:
   bool m_dcaYield[2];
   bool m_maxedLogged[2];

   int WaitHeartbeat() const
   {
      return Recovery_T165WaitLogSecondsPure(RecoveryWaitLogSeconds_);
   }

   void LogCapacityWait(const eRecoveryCoreDirection dir,
                        const int generation,
                        const string reason)
   {
      Log_WarnEvery("Recovery",
                    "t165capacity" + (string)Recovery_CycleKey(dir) +
                    "g" + (string)generation,
                    "T16.5 CAPACITY_WAIT " + Recovery_DirectionName(dir) +
                    " G" + (string)generation + ": " + reason +
                    "; không RECONCILE, không TesterStop, chặn thêm Core DCA và retry khi broker/margin cho phép",
                    WaitHeartbeat());
   }

   // T16.5 replacement for original ARCS BUILDING. A preflight or explicit
   // broker rejection with KNOWN no mutation is a capacity wait, not state
   // corruption. Only observed overfill or ambiguous execution stays fail-closed.
   bool DriveBuildingCapacitySafe(CExecutionLayer &exec,
                                  const eRecoveryCoreDirection dir,
                                  const datetime now,
                                  string &why)
   {
      why = "";
      int di = Idx(dir);
      if(m_dir[di].phase != ARCS_BUILDING) return false;

      int li = m_dir[di].activeLayer;
      SArcsLayer l;
      GetLayer(dir, li, l);
      if(!l.used || l.state != ARCS_LAYER_BUILDING)
      {
         LatchReconcile(dir, "BUILDING không có active layer hợp lệ");
         why = "BUILDING active layer invalid";
         return true;
      }

      int key = Recovery_CycleKey(dir);
      exec.ReconcileCycle(key);
      if(exec.HasReconcileRequired(key))
      {
         LatchReconcile(dir, "execution journal yêu cầu reconcile khi mở Hedge");
         why = "execution reconcile required";
         return true;
      }

      long live = Recovery_ArcsLayerUnits(dir, l.generation, m_volumeStep);
      if(live > l.targetUnits)
      {
         LatchReconcile(dir, "generation live volume vượt target");
         why = "generation over target";
         return true;
      }

      l.openedUnits = live;
      l.remainingUnits = live;
      if(live == l.targetUnits)
      {
         l.state = ARCS_LAYER_ACTIVE;
         PutLayer(dir, li, l);
         m_dir[di].phase = ARCS_ACTIVE;
         m_dirty = true;
         Save(why);
         return true;
      }
      PutLayer(dir, li, l);
      if(exec.HasPendingForCycle(key)) return true;

      SRecoveryBundleVolumeMeta meta;
      string preflightWhy = "";
      if(!Recovery_ReadBundleVolumeMeta(_Symbol, meta, preflightWhy))
      {
         LogCapacityWait(dir, l.generation, preflightWhy);
         return true;
      }

      long remaining = l.targetUnits - live;
      long child = Recovery_BundleNextChildUnits(remaining,
                                                 meta.minUnits,
                                                 meta.maxOrderUnits);
      if(child <= 0)
      {
         LogCapacityWait(dir, l.generation,
                         "phần volume còn lại chưa thể tạo child chính xác theo min/max/step broker");
         return true;
      }

      int hedgeDir = Recovery_HedgeDirection(dir);
      long existingDirectional = Recovery_DirectionalExposureUnits(_Symbol,
                                                                   hedgeDir,
                                                                   meta.volumeStep);
      if(!Recovery_VolumeLimitAllows(child, existingDirectional,
                                     meta.volumeLimitUnits))
      {
         LogCapacityWait(dir, l.generation,
                         "SYMBOL_VOLUME_LIMIT chưa cho phép Hedge child=" +
                         DoubleToString(Recovery_UnitsToVolume(child, meta.volumeStep), 2));
         return true;
      }

      if(!Recovery_ChildMarginPreflight(_Symbol, hedgeDir, child,
                                        meta.volumeStep, preflightWhy))
      {
         LogCapacityWait(dir, l.generation, preflightWhy);
         return true;
      }

      double volume = Recovery_UnitsToVolume(child, meta.volumeStep);
      int childNo = 1;
      SArcsPosition pos[];
      childNo += Recovery_ArcsBuildLayerPositions(dir, l.generation,
                                                  m_volumeStep, pos);
      string comment = "BDR|C=" + (string)key +
                       "|G=" + (string)l.generation +
                       "|B=" + (string)l.bundleId +
                       "|N=" + (string)childNo;
      if(!SaveBeforeMutation(why)) return true;

      bool accepted = exec.OpenMarketOwned(hedgeDir, volume,
                                           (long)RecoveryMagic_, key,
                                           EXEC_CMD_RECOVERY_OPEN,
                                           EXEC_RECONCILE_FAIL_CLOSED,
                                           comment);
      eRecoveryT165CapacityDisposition disposition =
         Recovery_T165CapacityDispositionPure(true, accepted,
                                               exec.HasReconcileRequired(key));
      if(disposition == RECOVERY_T165_CAPACITY_RECONCILE)
      {
         LatchReconcile(dir, "outcome mở ARCS Hedge không xác định");
         why = "ARCS Hedge child outcome ambiguous";
         return true;
      }
      if(disposition == RECOVERY_T165_CAPACITY_WAIT_NO_EFFECT)
      {
         LogCapacityWait(dir, l.generation,
                         "broker từ chối mở Hedge child với outcome xác định không có mutation");
         return true;
      }
      return true;
   }

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
         Log_WarnEvery("Recovery", "t163maxed" + (string)Recovery_CycleKey(dir),
                       "T16.3 MAXED_NO_HEDGE: đã đạt MaxHedgeGenerations=" +
                       (string)MaxHedgeGenerations_ +
                       ", Hedge=0 nhưng Core còn " +
                       DoubleToString(Recovery_UnitsToVolume(core, m_volumeStep), 2) +
                       " lot; cấm generation mới nhưng cho phép Core DCA/Overlap ổn định theo cấu hình",
                       WaitHeartbeat());
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
      Log_WarnEvery("Recovery", "t164maxorders" + (string)Recovery_CycleKey(dir),
                    "T16.4 Core DCA saturated: " + Recovery_DirectionName(dir) +
                    " count=" + (string)count +
                    " MaxOrders=" + (string)maxOrders +
                    "; RecoveryStartAfterDca=" + (string)RecoveryStartAfterDca_ +
                    " requiresCore=" + (string)required +
                    "; thresholdReachable=" + (reachable ? "yes" : "NO") +
                    "; ARCS phase=" + Recovery_ArcsPhaseName(m_dir[di].phase),
                    WaitHeartbeat());
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
      why = "";

      // T16.5 capacity wait intercepts BUILDING before the T16.0 base can turn
      // deterministic margin/volume preflight failures into RECONCILE.
      if(m_dir[0].phase == ARCS_BUILDING)
      {
         bool consumed = DriveBuildingCapacitySafe(exec, recovery_CORE_BUY,
                                                   ctx.now, why);
         UpdateMaxedTelemetry(recovery_CORE_BUY);
         UpdateMaxedTelemetry(recovery_CORE_SELL);
         return consumed;
      }
      if(m_dir[1].phase == ARCS_BUILDING)
      {
         bool consumed = DriveBuildingCapacitySafe(exec, recovery_CORE_SELL,
                                                   ctx.now, why);
         UpdateMaxedTelemetry(recovery_CORE_BUY);
         UpdateMaxedTelemetry(recovery_CORE_SELL);
         return consumed;
      }

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
               Log_WarnEvery("Recovery", "t163lockyield" + (string)Recovery_CycleKey(dir),
                             "T16.3 deferred-lock yield: retained Hedge vẫn chờ khóa, execution journal quiet; Core DCA được phép tiếp tục nếu ContinueDcaAfterHedge=true",
                             WaitHeartbeat());
               consumed = false;
               // The dedicated heartbeat above is the audit trail; suppress
               // duplicate Strategy ACTIVE-mutation warning for this wait.
               why = "";
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

#endif // BD_RECOVERY_ARCS_STACK_T165_WRAPPER_MQH
