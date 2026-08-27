//+------------------------------------------------------------------+
//| RecoveryArcsStackPostDeal.mqh — T16.2 runtime policy hardening   |
//| - preserves T16.1 symmetric protective-close event ordering      |
//| - explicit no-effect SL reject => defer/retry, not RECONCILE     |
//| - expected Overlap Core mutation => refresh ARCS broker state    |
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_ARCS_STACK_POST_DEAL_MQH
#define BD_RECOVERY_ARCS_STACK_POST_DEAL_MQH

#include "RecoveryArcsStackHardened.mqh"

class CRecoveryArcsStackFinal : public CRecoveryArcsStack
{
private:
   bool ResumeDealFirstClose(const eRecoveryCoreDirection dir,
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
         layer.protectiveCloseObservedAt > 0)
         return false;

      return AfterLayerLocked(dir, ctx.now, why);
   }

   bool FreshBrokerTick(double &bid, double &ask) const
   {
      bid = 0.0;
      ask = 0.0;
      MqlTick tick;
      if(!SymbolInfoTick(_Symbol, tick)) return false;
      bid = tick.bid;
      ask = tick.ask;
      return bid > 0.0 && ask > 0.0;
   }

   void LogDeferredBrokerSl(const string scope,
                            const eRecoveryCoreDirection dir,
                            const ulong ticket,
                            const double target,
                            const double bid,
                            const double ask,
                            const int stops,
                            const int freeze)
   {
      double required = (double)MathMax(stops, freeze) * _Point;
      double actual = dir == recovery_CORE_BUY ? target - ask : bid - target;
      Log_Warn("Recovery", "t162slreject" + scope + (string)Recovery_CycleKey(dir),
               "T16.2 " + scope + " SL broker reject có hiệu lực=0; giữ state và retry tick mới"
               " ticket=" + (string)ticket +
               " target=" + DoubleToString(target, _Digits) +
               " bid=" + DoubleToString(bid, _Digits) +
               " ask=" + DoubleToString(ask, _Digits) +
               " stops=" + (string)stops +
               " freeze=" + (string)freeze +
               " required=" + DoubleToString(required, _Digits) +
               " actual=" + DoubleToString(actual, _Digits));
   }

   // T16.2 replacement for the Broker-SL branch of DriveLockPending().
   // It is used only while the retained layer is still broker-observably live;
   // if the position vanished, control falls through to the T16.1 event-order
   // barrier so exact DEAL_ADD proof remains mandatory.
   bool DriveBrokerLockPendingSafe(CExecutionLayer &exec,
                                   const eRecoveryCoreDirection dir,
                                   const EAContext &ctx,
                                   string &why)
   {
      why = "";
      int di = Idx(dir);
      if(HedgeSLMode_ != SL_BROKER || m_dir[di].phase != ARCS_LOCK_PENDING ||
         m_dir[di].activeLayer < 0)
         return false;

      int li = m_dir[di].activeLayer;
      SArcsLayer l;
      GetLayer(dir, li, l);
      if(!l.used || l.state != ARCS_LAYER_LOCK_PENDING) return false;

      long live = Recovery_ArcsLayerUnits(dir, l.generation, m_volumeStep);
      if(live <= 0) return false; // T16.1 handles effect-before-DEAL ordering.
      l.remainingUnits = live;
      PutLayer(dir, li, l);

      SArcsPosition pos[];
      SArcsLayerSnapshot snap;
      if(!Recovery_ArcsLayerSnapshot(dir, l.generation, m_volumeStep,
                                     m_tickSize, pos, snap, why))
      {
         LatchReconcile(dir, why);
         return true;
      }
      double target = Recovery_LockTargetPricePure(dir,
                                                   snap.weightedEntry,
                                                   snap.netBE,
                                                   m_lockProfitPrice,
                                                   m_lockSafetyPrice,
                                                   m_tickSize,
                                                   _Digits);
      if(target <= 0.0)
      {
         LatchReconcile(dir, "không tính được SL dương cho retained generation");
         return true;
      }
      l.weightedEntry = snap.weightedEntry;
      l.netBE = snap.netBE;
      l.lockTargetPrice = target;
      PutLayer(dir, li, l);

      int key = Recovery_CycleKey(dir);
      exec.ReconcileCycle(key);
      if(exec.HasReconcileRequired(key))
      {
         LatchReconcile(dir, "broker SL modify cần reconcile");
         return true;
      }
      if(exec.HasPendingForCycle(key)) return true;

      int weak = -1;
      for(int i = 0; i < ArraySize(pos); i++)
      {
         if(!Recovery_LockSatisfiedPure(dir, pos[i].sl, target, m_tickSize))
         {
            weak = i;
            break;
         }
      }
      if(weak < 0)
      {
         l.state = ARCS_LAYER_LOCKED;
         PutLayer(dir, li, l);
         m_dir[di].phase = ARCS_LOCKED;
         AfterLayerLocked(dir, ctx.now, why);
         return true;
      }

      double freshBid = 0.0, freshAsk = 0.0;
      if(!FreshBrokerTick(freshBid, freshAsk))
      {
         why = "chưa lấy được fresh broker tick để validate SL dương";
         return true;
      }
      int stops = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
      int freeze = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
      if(!Recovery_LockBrokerDistanceValidPure(dir, target,
                                               freshBid, freshAsk, _Point,
                                               stops, freeze, m_tickSize))
      {
         why = "SL dương chưa đặt được theo fresh stops/freeze broker; giữ LOCK_PENDING";
         return true;
      }

      if(!SaveBeforeMutation(why)) return true;
      bool accepted = exec.ModifySlTpOwned(pos[weak].ticket, target, pos[weak].tp,
                                           (long)RecoveryMagic_, key,
                                           EXEC_CMD_RECOVERY_MODIFY,
                                           EXEC_RECONCILE_FAIL_CLOSED);
      eRecoveryModifyDisposition disposition =
         Recovery_T162ModifyDispositionPure(accepted, exec.HasReconcileRequired(key));
      if(disposition == RECOVERY_MODIFY_RECONCILE)
      {
         LatchReconcile(dir, "broker SL modify outcome ambiguous");
         return true;
      }
      if(disposition == RECOVERY_MODIFY_DEFER_NO_EFFECT)
      {
         LogDeferredBrokerSl("generation", dir, pos[weak].ticket, target,
                             freshBid, freshAsk, stops, freeze);
         why = "broker từ chối SL generation nhưng outcome xác định không có mutation; retry tick mới";
         return true;
      }
      return true;
   }

   // Same no-effect/ambiguous taxonomy for common Global SL. This prevents
   // fixing generation lock while leaving the identical failure class in the
   // multi-generation protection path.
   bool DriveBrokerGlobalProtectSafe(CExecutionLayer &exec,
                                     const eRecoveryCoreDirection dir,
                                     const EAContext &ctx,
                                     string &why)
   {
      why = "";
      int di = Idx(dir);
      if(HedgeSLMode_ != SL_BROKER || m_dir[di].phase != ARCS_GLOBAL_PROTECT)
         return false;

      long total = Recovery_ArcsTotalHedgeUnits(dir, m_volumeStep);
      if(total <= 0)
      {
         EnterTransition(dir, ctx.bid, ctx.ask);
         Save(why);
         return true;
      }

      double target = 0.0;
      if(!ComputeGlobalTarget(dir, target, why))
      {
         LatchReconcile(dir, why);
         return true;
      }
      m_dir[di].globalSlPrice = target;

      int key = Recovery_CycleKey(dir);
      exec.ReconcileCycle(key);
      if(exec.HasReconcileRequired(key))
      {
         LatchReconcile(dir, "Global SL broker modify cần reconcile");
         return true;
      }
      if(exec.HasPendingForCycle(key)) return true;

      double freshBid = 0.0, freshAsk = 0.0;
      if(!FreshBrokerTick(freshBid, freshAsk))
      {
         why = "chưa lấy được fresh broker tick để validate Global SL";
         return true;
      }
      int stops = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
      int freeze = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
      if(!Recovery_LockBrokerDistanceValidPure(dir, target,
                                               freshBid, freshAsk, _Point,
                                               stops, freeze, m_tickSize))
      {
         why = "Global SL chưa đặt được theo fresh stops/freeze broker; giữ GLOBAL_PROTECT";
         return true;
      }

      long wanted = Recovery_ArcsHedgeType(dir);
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol ||
            PositionGetInteger(POSITION_MAGIC) != (long)RecoveryMagic_ ||
            PositionGetInteger(POSITION_TYPE) != wanted)
            continue;
         double curSl = PositionGetDouble(POSITION_SL);
         if(Recovery_LockSatisfiedPure(dir, curSl, target, m_tickSize)) continue;
         double tp = PositionGetDouble(POSITION_TP);
         if(!SaveBeforeMutation(why)) return true;
         bool accepted = exec.ModifySlTpOwned(ticket, target, tp,
                                              (long)RecoveryMagic_, key,
                                              EXEC_CMD_RECOVERY_MODIFY,
                                              EXEC_RECONCILE_FAIL_CLOSED);
         eRecoveryModifyDisposition disposition =
            Recovery_T162ModifyDispositionPure(accepted, exec.HasReconcileRequired(key));
         if(disposition == RECOVERY_MODIFY_RECONCILE)
         {
            LatchReconcile(dir, "Global SL modify outcome ambiguous");
            return true;
         }
         if(disposition == RECOVERY_MODIFY_DEFER_NO_EFFECT)
         {
            LogDeferredBrokerSl("global", dir, ticket, target,
                                freshBid, freshAsk, stops, freeze);
            why = "broker từ chối Global SL nhưng outcome xác định không có mutation; retry tick mới";
            return true;
         }
         return true; // exactly one broker mutation per drive.
      }

      m_dir[di].globalSlArmed = true;
      m_dir[di].phase = ARCS_GLOBAL_ACTIVE;
      for(int i = 0; i < BD_ARCS_MAX_LAYERS; i++)
      {
         SArcsLayer l;
         GetLayer(dir, i, l);
         if(l.used && Recovery_ArcsLayerUnits(dir, l.generation, m_volumeStep) > 0)
         {
            l.state = ARCS_LAYER_GLOBAL_PROTECTED;
            PutLayer(dir, i, l);
         }
      }
      Save(why);
      return true;
   }

   bool RebaseArmedAfterExpectedCoreMutation(const eRecoveryCoreDirection dir,
                                             const datetime now,
                                             string &why)
   {
      int di = Idx(dir);
      if(m_dir[di].phase != ARCS_ARMED) return true;

      SArcsPosition core[];
      int count = Recovery_ArcsBuildCore(dir, m_volumeStep, core);
      if(!Recovery_DcaThresholdReached(count, RecoveryStartAfterDca_))
      {
         m_dir[di].armed = false;
         m_dir[di].phase = ARCS_IDLE;
         m_dir[di].anchorPosition = 0;
         m_dir[di].anchorPrice = 0.0;
         m_dir[di].anchorTicks = 0;
         m_dir[di].anchorTime = 0;
         m_dirty = true;
         return true;
      }

      ulong ticket = 0;
      double price = 0.0;
      datetime t = 0;
      if(!Recovery_ArcsThresholdAnchor(dir, m_volumeStep, ticket, price, t))
      {
         why = "Overlap đã đổi Core nhưng không rebuild được Recovery threshold anchor";
         return false;
      }
      m_dir[di].armed = true;
      m_dir[di].anchorPosition = ticket;
      m_dir[di].anchorPrice = price;
      m_dir[di].anchorTicks = Recovery_PriceToTicksPure(price, m_tickSize);
      m_dir[di].anchorTime = t > 0 ? t : now;
      m_dirty = true;
      return true;
   }

public:
   // T16.2 expected Overlap finalizer. Overlap P/L is Core-owned pair trimming,
   // not Hedge-funded Core loss, therefore it must not consume the ARCS cash
   // ledger. Only topology-dependent data is refreshed after exact broker DEALs.
   bool FinalizeExpectedOverlapMutation(CExecutionLayer &exec,
                                        const eRecoveryCoreDirection dir,
                                        const datetime now,
                                        string &why)
   {
      why = "";
      if(RecoveryMode_ != recovery_ACTIVE || !OverlapAfterHedge_ || !m_ready)
      {
         why = "T16.2 Overlap finalizer không ở trạng thái ACTIVE/ready/được bật";
         return false;
      }
      int key = Recovery_CycleKey(dir);
      exec.ReconcileCycle(key);
      if(exec.HasReconcileRequired(key))
      {
         why = "Overlap Core mutation có execution outcome ambiguous";
         LatchReconcile(dir, why);
         Save(why);
         return false;
      }
      if(exec.HasPendingForCycle(key) || m_pending[Idx(dir)].active)
      {
         why = "Overlap Core mutation chưa broker-quiet";
         return false;
      }

      // T17.14: a synchronous Core close can make protective broker-SL effects
      // visible before their deferred DEAL_ADD callbacks. Consume only exact
      // persisted-SL history proof before comparing live and persisted layers.
      string protectiveWhy = "";
      if(!RefreshExpectedProtectiveCloseOwnership(dir, protectiveWhy))
      {
         why = "post-Overlap protective ownership refresh failed: " + protectiveWhy;
         LatchReconcile(dir, why);
         Save(why);
         return false;
      }

      if(!ValidateLiveBook(dir, why))
      {
         LatchReconcile(dir, "post-Overlap ARCS live-book mismatch: " + why);
         Save(why);
         return false;
      }

      long core = Recovery_ArcsCoreUnits(dir, m_volumeStep);
      long hedge = Recovery_ArcsTotalHedgeUnits(dir, m_volumeStep);
      m_dir[Idx(dir)].lastObservedCoreUnits = core;
      m_dir[Idx(dir)].lastObservedHedgeUnits = hedge;

      if(!RebaseArmedAfterExpectedCoreMutation(dir, now, why))
      {
         LatchReconcile(dir, why);
         Save(why);
         return false;
      }

      m_dirty = true;
      if(!Save(why)) return false;
      Log_Info("Recovery", "T16.2 Overlap refresh complete for " +
               Recovery_DirectionName(dir) +
               " Core=" + DoubleToString(Recovery_UnitsToVolume(core, m_volumeStep), 2) +
               " Hedge=" + DoubleToString(Recovery_UnitsToVolume(hedge, m_volumeStep), 2) +
               " nextARCS=" + DoubleToString(
                    Recovery_UnitsToVolume(
                       Recovery_T162PostOverlapGenerationUnitsPure(RecoverySizingPolicy_,
                                                                  core, hedge,
                                                                  HedgeVolumePercent_),
                       m_volumeStep), 2));
      return true;
   }

   bool Drive(CExecutionLayer &exec, const EAContext &ctx, string &why)
   {
      why = "";

      // Preserve T16.1 DEAL-first symmetry before new policy branches.
      if(ResumeDealFirstClose(recovery_CORE_BUY, ctx, why)) return true;
      if(ResumeDealFirstClose(recovery_CORE_SELL, ctx, why)) return true;

      // Only intercept a live LOCK_PENDING position. If the broker effect is
      // already visible, the hardened base must enter PROTECTIVE_CLOSE_WAIT.
      if(HedgeSLMode_ == SL_BROKER)
      {
         int bi = Idx(recovery_CORE_BUY);
         if(m_dir[bi].phase == ARCS_LOCK_PENDING && m_dir[bi].activeLayer >= 0)
         {
            SArcsLayer l; GetLayer(recovery_CORE_BUY, m_dir[bi].activeLayer, l);
            if(l.used && Recovery_ArcsLayerUnits(recovery_CORE_BUY, l.generation, m_volumeStep) > 0)
               return DriveBrokerLockPendingSafe(exec, recovery_CORE_BUY, ctx, why);
         }
         int si = Idx(recovery_CORE_SELL);
         if(m_dir[si].phase == ARCS_LOCK_PENDING && m_dir[si].activeLayer >= 0)
         {
            SArcsLayer l; GetLayer(recovery_CORE_SELL, m_dir[si].activeLayer, l);
            if(l.used && Recovery_ArcsLayerUnits(recovery_CORE_SELL, l.generation, m_volumeStep) > 0)
               return DriveBrokerLockPendingSafe(exec, recovery_CORE_SELL, ctx, why);
         }
         if(m_dir[bi].phase == ARCS_GLOBAL_PROTECT)
            return DriveBrokerGlobalProtectSafe(exec, recovery_CORE_BUY, ctx, why);
         if(m_dir[si].phase == ARCS_GLOBAL_PROTECT)
            return DriveBrokerGlobalProtectSafe(exec, recovery_CORE_SELL, ctx, why);
      }

      return CRecoveryArcsStack::Drive(exec, ctx, why);
   }
};

#endif // BD_RECOVERY_ARCS_STACK_POST_DEAL_MQH
