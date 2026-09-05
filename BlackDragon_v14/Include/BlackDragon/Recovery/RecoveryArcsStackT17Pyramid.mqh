//+------------------------------------------------------------------+
//| RecoveryArcsStackT17Pyramid.mqh — T17.6 progressive Hedge       |
//| One logical coverage stage/bar + MinuteStop; child bundles exempt.|
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_ARCS_STACK_T17_PYRAMID_MQH
#define BD_RECOVERY_ARCS_STACK_T17_PYRAMID_MQH

#include <BlackDragon/Pyramid/PyramidConfig.mqh>
#include "RecoveryArcsStackPostDeal.mqh"

class CRecoveryArcsStackT17 : public CRecoveryArcsStackFinal
{
private:
   double m_cov[];
   double m_gap[];

   int Heartbeat() const
   {
      return Recovery_T165WaitLogSecondsPure(RecoveryWaitLogSeconds_);
   }

   void LogWait(const eRecoveryCoreDirection dir,
                const int generation,
                const string reason)
   {
      Log_WarnEvery("Recovery", "t17hedgepyr" + (string)Recovery_CycleKey(dir) +
                    "g" + (string)generation,
                    "T17.6 Hedge Pyramid WAIT " + Recovery_DirectionName(dir) +
                    " G" + (string)generation + ": " + reason,
                    Heartbeat());
   }

   bool BuildEffectiveCoverage(string &why)
   {
      why = "";
      ArrayResize(m_cov, 0);
      ArrayResize(m_gap, 0);
      if(HedgePyramidMode_ == hedge_pyramid_TAT) return true;

      double raw[];
      if(!Pyramid_ParsePositiveSequence(HedgePyramidCoverageSequence_, raw))
      { why = "không parse được chuỗi coverage Hedge Pyramid"; return false; }
      if(Pyramid_NormalizeCoverageTargetsPure(raw,
                                              HedgeVolumePercent_,
                                              HedgePyramidMaxCoveragePercent_,
                                              m_cov) <= 0)
      { why = "Hedge Pyramid không còn coverage hợp lệ sau khi áp trần"; return false; }

      if(ArraySize(m_cov) > 1)
      {
         if(!Pyramid_ParsePositiveSequence(HedgePyramidGapSequence_, m_gap))
         { why = "không parse được chuỗi khoảng cách Hedge Pyramid"; return false; }
      }
      return true;
   }

   long StageRawUnits(const eRecoveryCoreDirection dir,
                      const long liveGenerationUnits,
                      const double coverage) const
   {
      long core = Recovery_ArcsCoreUnits(dir, m_volumeStep);
      long total = Recovery_ArcsTotalHedgeUnits(dir, m_volumeStep);
      long before = total - liveGenerationUnits;
      if(before < 0) before = 0;
      long desired = Recovery_T16PercentUnitsPure(core, coverage);
      if(desired <= 0) return 0;
      // T17.6: staged coverage is TOTAL Recovery Hedge/Core coverage. Retained
      // prior generations count toward every stage regardless of the base ARCS
      // stacking policy. Hedge Pyramid therefore never exceeds its own staged
      // target merely because an older locked generation remains live.
      return desired > before ? desired - before : 0;
   }

   long StageUnits(const eRecoveryCoreDirection dir,
                   const long liveGenerationUnits,
                   const double coverage,
                   const long minUnits) const
   {
      long raw = StageRawUnits(dir, liveGenerationUnits, coverage);
      return Recovery_T166ClampPositiveGenerationUnitsPure(raw, minUnits);
   }

   bool HedgeGapHit(const eRecoveryCoreDirection dir,
                    const EAContext &ctx,
                    const double anchor,
                    const double gapPips) const
   {
      double gap = Recovery_PipsToPricePure(gapPips, m_isGold, _Point, _Digits);
      if(dir == recovery_CORE_BUY) return ctx.bid <= anchor - gap;
      return ctx.ask >= anchor + gap;
   }

   bool CurrentHedgeProfitable(const eRecoveryCoreDirection dir,
                               const EAContext &ctx,
                               SArcsLayerSnapshot &snap,
                               string &why)
   {
      SArcsPosition pos[];
      if(!Recovery_ArcsLayerSnapshot(dir,
                                     m_dir[Idx(dir)].generationCount,
                                     m_volumeStep, m_tickSize,
                                     pos, snap, why)) return false;
      return dir == recovery_CORE_BUY ? ctx.ask < snap.netBE
                                      : ctx.bid > snap.netBE;
   }

   bool ActivateCurrentVolume(const eRecoveryCoreDirection dir,
                              const int li,
                              SArcsLayer &l,
                              const long live,
                              string &why)
   {
      if(live <= 0) return false;
      l.targetUnits = live;
      l.openedUnits = live;
      l.remainingUnits = live;
      l.state = ARCS_LAYER_ACTIVE;
      PutLayer(dir, li, l);
      m_dir[Idx(dir)].phase = ARCS_ACTIVE;
      m_dirty = true;
      return Save(why);
   }

   bool TpPriorityRequiresActivation(const eRecoveryCoreDirection dir,
                                     const EAContext &ctx,
                                     const int li,
                                     SArcsLayer &l,
                                     const long live,
                                     string &why)
   {
      if(live <= 0) return false;
      SArcsPosition pos[];
      SArcsLayerSnapshot snap;
      string local = "";
      if(!Recovery_ArcsLayerSnapshot(dir, l.generation, m_volumeStep,
                                     m_tickSize, pos, snap, local)) return false;
      if(Recovery_VirtualHedgeTpHit(dir, snap.netBE, ctx.bid, ctx.ask,
                                    m_tpDistancePrice))
      {
         why = "T17.6 ưu tiên TP: dừng tăng coverage và kích hoạt volume Hedge hiện tại";
         ActivateCurrentVolume(dir, li, l, live, local);
         return true;
      }
      return false;
   }

   bool ProjectedRoomAllows(const eRecoveryCoreDirection dir,
                            const EAContext &ctx,
                            const SArcsLayerSnapshot &snap,
                            const long addUnits) const
   {
      if(HedgePyramidMinRoomToTPPips_ <= 0.0 || addUnits <= 0) return true;
      double addLots = Recovery_UnitsToVolume(addUnits, m_volumeStep);
      if(addLots <= 0.0 || snap.lots <= 0.0) return false;
      double entry = dir == recovery_CORE_BUY ? ctx.bid : ctx.ask;
      double projectedLots = snap.lots + addLots;
      double projectedBE = (snap.weightedEntry * snap.lots + entry * addLots) / projectedLots;
      double target = dir == recovery_CORE_BUY ? projectedBE - m_tpDistancePrice
                                               : projectedBE + m_tpDistancePrice;
      double pip = Recovery_PipSizePure(m_isGold, _Point, _Digits);
      if(pip <= 0.0) return false;
      double room = dir == recovery_CORE_BUY ? (ctx.ask - target) / pip
                                             : (target - ctx.bid) / pip;
      return room + 1e-9 >= HedgePyramidMinRoomToTPPips_;
   }

   bool FullMarginReserveAllows(const eRecoveryCoreDirection dir,
                               const long remainingUnits,
                               const SRecoveryBundleVolumeMeta &meta,
                               string &why) const
   {
      why = "";
      if(!HedgePyramidReserveFullTarget_ || remainingUnits <= 0) return true;
      int hedgeDir = Recovery_HedgeDirection(dir);
      ENUM_ORDER_TYPE type = hedgeDir == 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      MqlTick tick;
      if(!SymbolInfoTick(_Symbol, tick))
      { why = "không đọc được tick để reserve margin full Hedge target"; return false; }
      double price = hedgeDir == 0 ? tick.ask : tick.bid;
      long left = remainingUnits;
      double required = 0.0;
      while(left > 0)
      {
         long child = Recovery_BundleNextChildUnits(left, meta.minUnits, meta.maxOrderUnits);
         if(child <= 0)
         { why = "full Hedge target không bundle được theo min/max broker"; return false; }
         double margin = 0.0;
         double volume = Recovery_UnitsToVolume(child, meta.volumeStep);
         if(!OrderCalcMargin(type, _Symbol, volume, price, margin) || margin < 0.0)
         { why = "OrderCalcMargin thất bại khi reserve full Hedge target"; return false; }
         required += margin;
         left -= child;
      }
      double free = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      if(free + 1e-8 < required)
      {
         why = "Free Margin=" + DoubleToString(free, 2) +
               " < reserve full Hedge target=" + DoubleToString(required, 2);
         return false;
      }
      return true;
   }

   bool DriveBuildingPyramid(CExecutionLayer &exec,
                             const eRecoveryCoreDirection dir,
                             const EAContext &ctx,
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
         LatchReconcile(dir, "T17.6 BUILDING không có active layer hợp lệ");
         why = "T17.6 BUILDING active layer invalid";
         return true;
      }

      int key = Recovery_CycleKey(dir);
      exec.ReconcileCycle(key);
      if(exec.HasReconcileRequired(key))
      {
         LatchReconcile(dir, "T17.6 execution journal yêu cầu reconcile khi mở Hedge");
         why = "T17.6 Hedge Pyramid execution reconcile required";
         return true;
      }

      long live = Recovery_ArcsLayerUnits(dir, l.generation, m_volumeStep);
      // Preserve the strict broker-ownership invariant. Dynamic policy rebase
      // may change the computed target, but a broker-observed generation may
      // never exceed the target that was actually persisted before mutation.
      if(live > l.targetUnits)
      {
         LatchReconcile(dir, "T17.6 generation live volume vượt persisted target");
         why = "T17.6 generation over persisted target";
         return true;
      }
      l.openedUnits = live;
      l.remainingUnits = live;
      PutLayer(dir, li, l);

      SRecoveryBundleVolumeMeta meta;
      string preflight = "";
      if(!Recovery_ReadBundleVolumeMeta(_Symbol, meta, preflight))
      { LogWait(dir, l.generation, preflight); return true; }

      long computedFinalTarget = StageUnits(dir, live,
                                            m_cov[ArraySize(m_cov)-1],
                                            meta.minUnits);
      long finalTarget = Recovery_T176RebasedGenerationTargetPure(live,
                                                                  computedFinalTarget);
      // A zero target with no current-generation exposure means topology moved
      // outside the staged plan before any child existed. That edge is not the
      // observed T17.5 failure and is kept fail-closed rather than inventing a
      // layer-cancellation/re-entry transition without a locking test.
      if(finalTarget <= 0 && live <= 0)
      {
         LatchReconcile(dir, "T17.6 BUILDING target collapsed to zero before first child; explicit transition proof required");
         why = "T17.6 empty BUILDING target collapsed to zero";
         return true;
      }
      if(finalTarget != l.targetUnits)
      {
         long oldTarget = l.targetUnits;
         l.targetUnits = finalTarget;
         PutLayer(dir, li, l);
         m_dirty = true;
         if(!Save(why)) return true;
         Log_Info("Recovery", "T17.6 Hedge Pyramid target rebase " +
                  Recovery_DirectionName(dir) + " G" + (string)l.generation +
                  " old=" + DoubleToString(Recovery_UnitsToVolume(oldTarget, m_volumeStep), 2) +
                  " new=" + DoubleToString(Recovery_UnitsToVolume(finalTarget, m_volumeStep), 2) +
                  " live=" + DoubleToString(Recovery_UnitsToVolume(live, m_volumeStep), 2));
      }

      if(live == l.targetUnits)
      {
         l.state = ARCS_LAYER_ACTIVE;
         PutLayer(dir, li, l);
         m_dir[di].phase = ARCS_ACTIVE;
         m_dirty = true;
         Save(why);
         return true;
      }
      if(exec.HasPendingForCycle(key)) return true;
      if(TpPriorityRequiresActivation(dir, ctx, li, l, live, why)) return true;

      int stage = -1;
      long stageTarget = 0;
      long previousTarget = 0;
      for(int i = 0; i < ArraySize(m_cov); i++)
      {
         long t = StageUnits(dir, live, m_cov[i], meta.minUnits);
         if(t <= previousTarget) continue;
         if(live < t)
         {
            stage = i;
            stageTarget = t;
            break;
         }
         previousTarget = t;
      }
      if(stage < 0)
      {
         if(live > 0) ActivateCurrentVolume(dir, li, l, live, why);
         return true;
      }

      // Multiple broker child orders may complete ONE logical stage without
      // a bar/minute wait. Timing applies only when crossing to a NEW stage.
      bool continuingPartialStage = live > previousTarget;
      if(!continuingPartialStage && live > 0)
      {
         SArcsPosition pos[];
         Recovery_ArcsBuildLayerPositions(dir, l.generation, m_volumeStep, pos);
         if(ArraySize(pos) <= 0)
         { LatchReconcile(dir, "T17.6 không tìm thấy Hedge anchor cho bậc coverage tiếp theo"); return true; }

         datetime lastStageOpen = pos[ArraySize(pos)-1].openTime;
         datetime lastStageBar = (lastStageOpen >= ctx.barTime) ? ctx.barTime : 0;
         if(!Pyramid_AddTimingAllowsPure(lastStageOpen, lastStageBar,
                                         ctx.now, ctx.barTime, MinuteStop))
         {
            LogWait(dir, l.generation, "chờ nến mới/MinuteStop trước bậc coverage mới");
            return true;
         }

         double anchor = pos[ArraySize(pos)-1].openPrice;
         double gapPips = Pyramid_SeqValue(m_gap, stage - 1);
         if(!HedgeGapHit(dir, ctx, anchor, gapPips))
         {
            LogWait(dir, l.generation,
                    "đang giữ coverage " + DoubleToString(m_cov[stage-1], 2) +
                    "%; chờ Hedge đi thuận thêm " + DoubleToString(gapPips, 2) + " pip");
            return true;
         }
         if(HedgePyramidLockBeforeAdd_)
         {
            SArcsLayerSnapshot snap;
            string local = "";
            if(!CurrentHedgeProfitable(dir, ctx, snap, local))
            {
               LogWait(dir, l.generation, "Hedge hiện tại chưa ở phía lợi nhuận ròng; chưa tăng coverage");
               return true;
            }
         }
      }

      long remainingStage = stageTarget - live;
      if(remainingStage <= 0) return true;
      SArcsLayerSnapshot snap;
      if(live > 0)
      {
         SArcsPosition pos[];
         string local = "";
         if(!Recovery_ArcsLayerSnapshot(dir, l.generation, m_volumeStep,
                                        m_tickSize, pos, snap, local))
         { LatchReconcile(dir, local); why = local; return true; }
         if(!ProjectedRoomAllows(dir, ctx, snap, remainingStage))
         {
            why = "T17.6 ưu tiên TP: room-to-TP không đủ để tăng coverage";
            ActivateCurrentVolume(dir, li, l, live, preflight);
            return true;
         }
      }

      if(live == 0 && !FullMarginReserveAllows(dir, l.targetUnits, meta, preflight))
      { LogWait(dir, l.generation, preflight); return true; }

      long child = Recovery_BundleNextChildUnits(remainingStage,
                                                 meta.minUnits,
                                                 meta.maxOrderUnits);
      if(child <= 0)
      { LogWait(dir, l.generation, "bậc coverage còn lại chưa bundle được theo min/max broker"); return true; }

      int hedgeDir = Recovery_HedgeDirection(dir);
      long existingDirectional = Recovery_DirectionalExposureUnits(_Symbol, hedgeDir, meta.volumeStep);
      if(!Recovery_VolumeLimitAllows(child, existingDirectional, meta.volumeLimitUnits))
      { LogWait(dir, l.generation, "SYMBOL_VOLUME_LIMIT chưa cho phép child Hedge Pyramid"); return true; }
      if(!Recovery_ChildMarginPreflight(_Symbol, hedgeDir, child, meta.volumeStep, preflight))
      { LogWait(dir, l.generation, preflight); return true; }

      if(!Recovery_OneOrderPerBarAllows(hedgeDir, TimeCurrent(), why))
      {
         Log_WarnEvery("Recovery", "t1720bar" + (string)key, why, 60);
         return true;
      }

      double volume = Recovery_UnitsToVolume(child, meta.volumeStep);
      SArcsPosition pos[];
      int childNo = 1 + Recovery_ArcsBuildLayerPositions(dir, l.generation, m_volumeStep, pos);
      string comment = Recovery_BuildReadableComment(key, l.generation, l.bundleId,
                                      (stage + 1), childNo,
                                      m_dir[Idx(dir)].transitionReferencePrice > 0.0);
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
         LatchReconcile(dir, "T17.6 outcome mở Hedge Pyramid không xác định");
         why = "T17.6 Hedge Pyramid child outcome ambiguous";
         return true;
      }
      if(disposition == RECOVERY_T165_CAPACITY_WAIT_NO_EFFECT)
      {
         LogWait(dir, l.generation, "broker từ chối child Hedge Pyramid với outcome xác định không mutation");
         return true;
      }
      Log_Info("Recovery", "T17.6 Hedge Pyramid " + Recovery_DirectionName(dir) +
               " G" + (string)l.generation + " P" + (string)(stage + 1) +
               " targetCoverage=" + DoubleToString(m_cov[stage], 2) +
               "% child=" + DoubleToString(volume, 2) + " lot");
      return true;
   }

public:
   CRecoveryArcsStackT17(void) : CRecoveryArcsStackFinal() {}

   bool Init()
   {
      string why = "";
      if(!Pyramid_ValidateConfig(why))
      {
         Log_Error("Recovery", "T17.6 Pyramid config invalid: " + why);
         return false;
      }
      if(!BuildEffectiveCoverage(why))
      {
         Log_Error("Recovery", "T17.6 Hedge Pyramid config invalid: " + why);
         return false;
      }
      if(HedgePyramidMode_ != hedge_pyramid_TAT && HedgeTPPips_ > 0.0 &&
         HedgePyramidMinRoomToTPPips_ >= HedgeTPPips_)
         Log_Warn("Recovery", "t176hedgereach",
                  "HedgePyramidMinRoomToTPPips_ >= HedgeTPPips_: bậc coverage sau có thể không reachable trước TP");
      return CRecoveryArcsStackFinal::Init();
   }

   bool Drive(CExecutionLayer &exec, const EAContext &ctx, string &why)
   {
      if(HedgePyramidMode_ != hedge_pyramid_TAT)
      {
         if(m_dir[0].phase == ARCS_BUILDING)
            return DriveBuildingPyramid(exec, recovery_CORE_BUY, ctx, why);
         if(m_dir[1].phase == ARCS_BUILDING)
            return DriveBuildingPyramid(exec, recovery_CORE_SELL, ctx, why);
      }
      return CRecoveryArcsStackFinal::Drive(exec, ctx, why);
   }
};

#endif // BD_RECOVERY_ARCS_STACK_T17_PYRAMID_MQH
