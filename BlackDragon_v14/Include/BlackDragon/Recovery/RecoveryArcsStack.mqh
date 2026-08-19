//+------------------------------------------------------------------+
//| RecoveryArcsStack.mqh — T16 ARCS stacked Recovery engine         |
//| Source-of-truth sequence:                                        |
//| active layer TP -> partial close -> confirmed cash funds Core -> |
//| retained layer lock -> immediate next layer sized from Core.     |
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_ARCS_STACK_MQH
#define BD_RECOVERY_ARCS_STACK_MQH

#include "RecoveryArcsBook.mqh"
#include <BlackDragon/ExecutionLayer.mqh>
#include <BlackDragon/Logger.mqh>

class CRecoveryArcsStack
{
private:
   SArcsDirection        m_dir[2];
   SArcsExternalPending  m_pending[2];
   SArcsLayer            m_buyLayers[];
   SArcsLayer            m_sellLayers[];
   CRecoveryArcsPersistence m_persistence;
   bool   m_initialized;
   bool   m_ready;
   bool   m_persistLoaded;
   bool   m_persistMissing;
   bool   m_persistenceBlocked;
   bool   m_dirty;
   long   m_saveSequence;
   double m_volumeStep;
   double m_tickSize;
   bool   m_isGold;
   long   m_initialGapTicks;
   double m_tpDistancePrice;
   double m_lockProfitPrice;
   double m_lockSafetyPrice;
   double m_globalProfitPrice;
   long   m_reentryBufferTicks;
   string m_startupFault;

   int Idx(const eRecoveryCoreDirection dir) const
   {
      return dir == recovery_CORE_BUY ? 0 : 1;
   }

   void GetLayer(const eRecoveryCoreDirection dir,
                 const int index,
                 SArcsLayer &out) const
   {
      if(index < 0 || index >= BD_ARCS_MAX_LAYERS)
      {
         Recovery_ArcsLayerReset(out);
         return;
      }
      out = dir == recovery_CORE_BUY ? m_buyLayers[index] : m_sellLayers[index];
   }

   void PutLayer(const eRecoveryCoreDirection dir,
                 const int index,
                 const SArcsLayer &value)
   {
      if(index < 0 || index >= BD_ARCS_MAX_LAYERS) return;
      if(dir == recovery_CORE_BUY) m_buyLayers[index] = value;
      else m_sellLayers[index] = value;
      m_dirty = true;
   }

   void ResetLayers(const eRecoveryCoreDirection dir)
   {
      for(int i = 0; i < BD_ARCS_MAX_LAYERS; i++)
      {
         SArcsLayer l;
         Recovery_ArcsLayerReset(l);
         PutLayer(dir, i, l);
      }
   }

   int FindLayerByGeneration(const eRecoveryCoreDirection dir,
                             const int generation) const
   {
      if(generation < 1) return -1;
      for(int i = 0; i < BD_ARCS_MAX_LAYERS; i++)
      {
         SArcsLayer l;
         GetLayer(dir, i, l);
         if(l.used && l.generation == generation) return i;
      }
      return -1;
   }

   int FindFreeLayer(const eRecoveryCoreDirection dir) const
   {
      for(int i = 0; i < BD_ARCS_MAX_LAYERS; i++)
      {
         SArcsLayer l;
         GetLayer(dir, i, l);
         if(!l.used || l.state == ARCS_LAYER_EMPTY || l.state == ARCS_LAYER_CLOSED)
            return i;
      }
      return -1;
   }

   int LiveLayerCount(const eRecoveryCoreDirection dir) const
   {
      int n = 0;
      for(int i = 0; i < BD_ARCS_MAX_LAYERS; i++)
      {
         SArcsLayer l;
         GetLayer(dir, i, l);
         if(l.used && l.remainingUnits > 0 && Recovery_ArcsLayerStateHasExposure(l.state)) n++;
      }
      return n;
   }

   bool Save(string &why)
   {
      why = "";
      if(RecoveryMode_ != recovery_ACTIVE) { m_dirty = false; return true; }
      if(m_persistenceBlocked)
      {
         why = "ARCS persistence đang bị khóa do lỗi startup/identity";
         return false;
      }
      if(!m_persistence.Save(m_saveSequence + 1,
                             m_dir[0], m_dir[1],
                             m_pending[0], m_pending[1],
                             m_buyLayers, m_sellLayers, why))
      {
         m_ready = false;
         return false;
      }
      m_saveSequence++;
      m_dirty = false;
      return true;
   }

   bool SaveBeforeMutation(string &why)
   {
      m_dirty = true;
      return Save(why);
   }

   void LatchReconcile(const eRecoveryCoreDirection dir,
                       const string reason)
   {
      int i = Idx(dir);
      m_dir[i].phase = ARCS_RECONCILE;
      m_dir[i].reconcileRequired = true;
      m_ready = false;
      m_dirty = true;
      Log_Error("Recovery", "T16 ARCS reconcile required for " +
                Recovery_DirectionName(dir) + ": " + reason);
   }

   long TotalOwnerUnits(const eRecoveryCoreDirection dir,
                        const long ownerMagic) const
   {
      if(ownerMagic == (long)Magic)
         return Recovery_ArcsCoreUnits(dir, m_volumeStep);
      if(ownerMagic == (long)RecoveryMagic_)
         return Recovery_ArcsTotalHedgeUnits(dir, m_volumeStep);
      return 0;
   }

   bool CursorAfter(const long tmsc, const ulong ticket,
                    const long cursorMsc, const ulong cursorTicket) const
   {
      return tmsc > cursorMsc || (tmsc == cursorMsc && ticket > cursorTicket);
   }

   void TrackCursor(const eRecoveryCoreDirection dir, const ulong deal)
   {
      if(deal == 0 || !HistoryDealSelect(deal)) return;
      int i = Idx(dir);
      long tmsc = HistoryDealGetInteger(deal, DEAL_TIME_MSC);
      if(CursorAfter(tmsc, deal, m_dir[i].lastDealTimeMsc, m_dir[i].lastDealTicket))
      {
         m_dir[i].lastDealTimeMsc = tmsc;
         m_dir[i].lastDealTicket = deal;
         m_dirty = true;
      }
   }

   long ResolveClosedOwnerMagic(const ulong deal)
   {
      if(deal == 0 || !HistoryDealSelect(deal)) return 0;
      long direct = HistoryDealGetInteger(deal, DEAL_MAGIC);
      if(direct == (long)Magic || direct == (long)RecoveryMagic_) return direct;
      ulong positionId = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
      if(positionId == 0 || !HistorySelectByPosition(positionId)) return direct;
      ulong oldest = 0;
      long oldestMsc = 0;
      long owner = direct;
      for(int i = 0; i < HistoryDealsTotal(); i++)
      {
         ulong d = HistoryDealGetTicket(i);
         if(d == 0 || HistoryDealGetString(d, DEAL_SYMBOL) != _Symbol) continue;
         long entry = HistoryDealGetInteger(d, DEAL_ENTRY);
         if(entry != DEAL_ENTRY_IN && entry != DEAL_ENTRY_INOUT) continue;
         long t = HistoryDealGetInteger(d, DEAL_TIME_MSC);
         if(oldest == 0 || t < oldestMsc || (t == oldestMsc && d < oldest))
         {
            oldest = d;
            oldestMsc = t;
            owner = HistoryDealGetInteger(d, DEAL_MAGIC);
         }
      }
      return owner;
   }

   eRecoveryCoreDirection DirectionForClose(const long ownerMagic,
                                            const long dealType,
                                            bool &mapped) const
   {
      mapped = true;
      if(ownerMagic == (long)RecoveryMagic_)
      {
         if(dealType == DEAL_TYPE_BUY) return recovery_CORE_BUY;  // closes SELL hedge
         if(dealType == DEAL_TYPE_SELL) return recovery_CORE_SELL;// closes BUY hedge
      }
      else if(ownerMagic == (long)Magic)
      {
         if(dealType == DEAL_TYPE_SELL) return recovery_CORE_BUY; // closes BUY Core
         if(dealType == DEAL_TYPE_BUY) return recovery_CORE_SELL; // closes SELL Core
      }
      mapped = false;
      return recovery_CORE_BUY;
   }

   void ApplyCloseDeal(const ulong deal)
   {
      if(deal == 0 || !HistoryDealSelect(deal)) return;
      long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY) return;
      long owner = ResolveClosedOwnerMagic(deal);
      if(owner != (long)Magic && owner != (long)RecoveryMagic_) return;
      if(!HistoryDealSelect(deal)) return;
      long type = HistoryDealGetInteger(deal, DEAL_TYPE);
      bool mapped = false;
      eRecoveryCoreDirection dir = DirectionForClose(owner, type, mapped);
      if(!mapped) return;
      int di = Idx(dir);
      double cash = Recovery_DealCashPure(HistoryDealGetDouble(deal, DEAL_PROFIT),
                                          HistoryDealGetDouble(deal, DEAL_SWAP),
                                          HistoryDealGetDouble(deal, DEAL_COMMISSION),
                                          HistoryDealGetDouble(deal, DEAL_FEE));
      if(owner == (long)RecoveryMagic_)
      {
         ulong posId = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
         int generation = Recovery_ArcsGenerationFromPositionHistory(posId);
         int li = FindLayerByGeneration(dir, generation);
         if(li >= 0)
         {
            SArcsLayer l;
            GetLayer(dir, li, l);
            long units = Recovery_VolumeToUnitsFloor(HistoryDealGetDouble(deal, DEAL_VOLUME), m_volumeStep);
            if(l.state == ARCS_LAYER_TP_PENDING && m_dir[di].phase == ARCS_TP_PENDING)
            {
               l.fundingClosedUnits += units;
               l.realizedFundingCash += cash;
               m_dir[di].hedgeFundingCash += cash;
               Recovery_ArcsRecomputeCredit(m_dir[di]);
            }
            else
               l.realizedOtherCash += cash;
            PutLayer(dir, li, l);
         }
      }
      else if(m_dir[di].phase == ARCS_CORE_FUNDING && cash < 0.0)
      {
         m_dir[di].coreLossSpent += -cash;
         Recovery_ArcsRecomputeCredit(m_dir[di]);
      }
      TrackCursor(dir, deal);
   }

   bool ReplayAfterCursor(const eRecoveryCoreDirection dir, string &why)
   {
      why = "";
      int di = Idx(dir);
      if(!HistorySelect(0, TimeCurrent()))
      {
         why = "không đọc được history để replay ARCS";
         return false;
      }
      ulong replay[];
      ArrayResize(replay, 0);
      for(int i = 0; i < HistoryDealsTotal(); i++)
      {
         ulong deal = HistoryDealGetTicket(i);
         if(deal == 0 || HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol) continue;
         long tmsc = HistoryDealGetInteger(deal, DEAL_TIME_MSC);
         if(!CursorAfter(tmsc, deal, m_dir[di].lastDealTimeMsc,
                         m_dir[di].lastDealTicket)) continue;
         long magic = HistoryDealGetInteger(deal, DEAL_MAGIC);
         if(magic != (long)Magic && magic != (long)RecoveryMagic_ && magic != 0) continue;
         int n = ArraySize(replay);
         ArrayResize(replay, n + 1);
         replay[n] = deal;
      }
      for(int i = 0; i < ArraySize(replay); i++) ApplyCloseDeal(replay[i]);
      return true;
   }

   bool ValidateLiveBook(const eRecoveryCoreDirection dir, string &why)
   {
      why = "";
      long registered = 0;
      for(int i = 0; i < BD_ARCS_MAX_LAYERS; i++)
      {
         SArcsLayer l;
         GetLayer(dir, i, l);
         if(!l.used) continue;
         long live = Recovery_ArcsLayerUnits(dir, l.generation, m_volumeStep);
         if(l.state == ARCS_LAYER_BUILDING)
         {
            if(live < 0 || live > l.targetUnits)
            {
               why = "generation BUILDING vượt target đã persist";
               return false;
            }
            l.openedUnits = live;
            l.remainingUnits = live;
            if(live == l.targetUnits)
            {
               l.state = ARCS_LAYER_ACTIVE;
               m_dir[Idx(dir)].phase = ARCS_ACTIVE;
            }
            PutLayer(dir, i, l);
         }
         else if(l.state == ARCS_LAYER_TP_PENDING)
         {
            long closed = l.tpBaselineUnits - live;
            if(closed < 0 || closed > l.tpTargetCloseUnits)
            {
               why = "generation TP_PENDING có volume ngoài target";
               return false;
            }
            l.tpObservedCloseUnits = closed;
            l.remainingUnits = live;
            PutLayer(dir, i, l);
         }
         else if(Recovery_ArcsLayerStateHasExposure(l.state))
         {
            if(live != l.remainingUnits)
            {
               why = "live generation volume khác persisted layer ownership";
               return false;
            }
         }
         else if((l.state == ARCS_LAYER_CLOSED || l.state == ARCS_LAYER_EMPTY) && live != 0)
         {
            why = "layer CLOSED/EMPTY vẫn có broker exposure";
            return false;
         }
         registered += live;
      }

      long total = Recovery_ArcsTotalHedgeUnits(dir, m_volumeStep);
      if(total != registered)
      {
         why = "RecoveryMagic exposure không map đầy đủ vào generation registry";
         return false;
      }
      eArcsPhase p = m_dir[Idx(dir)].phase;
      if((p == ARCS_IDLE || p == ARCS_ARMED || p == ARCS_REVERSAL_HOLD) && total > 0)
      {
         why = "phase không sở hữu Hedge nhưng broker vẫn có Recovery exposure";
         return false;
      }
      return true;
   }

   void ResetDirection(const eRecoveryCoreDirection dir)
   {
      int i = Idx(dir);
      Recovery_ArcsDirectionReset(m_dir[i]);
      Recovery_ArcsPendingReset(m_pending[i]);
      ResetLayers(dir);
      m_dirty = true;
   }

   bool ArmFromCore(const eRecoveryCoreDirection dir, const datetime now)
   {
      int di = Idx(dir);
      if(m_dir[di].phase != ARCS_IDLE) return false;
      SArcsPosition core[];
      int count = Recovery_ArcsBuildCore(dir, m_volumeStep, core);
      if(!Recovery_DcaThresholdReached(count, RecoveryStartAfterDca_)) return false;
      ulong ticket = 0;
      double price = 0.0;
      datetime t = 0;
      if(!Recovery_ArcsThresholdAnchor(dir, m_volumeStep, ticket, price, t)) return false;
      m_dir[di].armed = true;
      m_dir[di].phase = ARCS_ARMED;
      m_dir[di].anchorPosition = ticket;
      m_dir[di].anchorPrice = price;
      m_dir[di].anchorTicks = Recovery_PriceToTicksPure(price, m_tickSize);
      m_dir[di].anchorTime = t > 0 ? t : now;
      m_dirty = true;
      Log_Info("Recovery", "T16 ARCS " + Recovery_DirectionName(dir) +
               " armed anchor=" + DoubleToString(price, _Digits) +
               " Core=" + DoubleToString((double)Recovery_ArcsCoreUnits(dir, m_volumeStep) * m_volumeStep, 2));
      return true;
   }

   bool InitialGapHit(const eRecoveryCoreDirection dir,
                      const EAContext &ctx) const
   {
      const SArcsDirection d = m_dir[Idx(dir)];
      long bidTicks = Recovery_PriceToTicksPure(ctx.bid, m_tickSize);
      long askTicks = Recovery_PriceToTicksPure(ctx.ask, m_tickSize);
      return Recovery_AdverseGapHitTicks(dir, d.anchorTicks,
                                         bidTicks, askTicks,
                                         m_initialGapTicks);
   }

   bool StartGeneration(const eRecoveryCoreDirection dir,
                        const datetime now,
                        string &why)
   {
      why = "";
      int di = Idx(dir);
      long coreUnits = Recovery_ArcsCoreUnits(dir, m_volumeStep);
      long existing = Recovery_ArcsTotalHedgeUnits(dir, m_volumeStep);
      if(coreUnits <= 0)
      {
         why = "Core đã phẳng; không cần mở generation mới";
         return false;
      }
      if(m_dir[di].generationCount >= MaxHedgeGenerations_)
      {
         why = "đã đạt Số vòng Hedge tối đa";
         m_dir[di].phase = ARCS_LOCKED;
         m_dirty = true;
         return false;
      }
      long target = Recovery_T16NewGenerationUnitsPure(RecoverySizingPolicy_,
                                                       coreUnits, existing,
                                                       HedgeVolumePercent_);
      SRecoveryBundleVolumeMeta meta;
      if(!Recovery_ReadBundleVolumeMeta(_Symbol, meta, why)) return false;
      if(target < meta.minUnits)
      {
         why = "khối lượng generation theo % Hedge nhỏ hơn volume tối thiểu broker";
         LatchReconcile(dir, why);
         return false;
      }
      int slot = FindFreeLayer(dir);
      if(slot < 0)
      {
         why = "layer registry ARCS đã đầy";
         LatchReconcile(dir, why);
         return false;
      }
      int generation = m_dir[di].generationCount + 1;
      SArcsLayer l;
      Recovery_ArcsLayerReset(l);
      l.used = true;
      l.generation = generation;
      l.bundleId = generation;
      l.state = ARCS_LAYER_BUILDING;
      l.targetUnits = target;
      l.openedUnits = 0;
      l.remainingUnits = 0;
      PutLayer(dir, slot, l);
      m_dir[di].generationCount = generation;
      m_dir[di].activeLayer = slot;
      m_dir[di].phase = ARCS_BUILDING;
      m_dirty = true;
      Log_Info("Recovery", "T16 ARCS " + Recovery_DirectionName(dir) +
               " start G" + (string)generation +
               " target=" + DoubleToString(Recovery_UnitsToVolume(target, m_volumeStep), 2) +
               " lot (Core x " + DoubleToString(HedgeVolumePercent_, 2) + "%)");
      return true;
   }

   bool DriveBuilding(CExecutionLayer &exec,
                      const eRecoveryCoreDirection dir,
                      const datetime now,
                      string &why)
   {
      why = "";
      int di = Idx(dir);
      int li = m_dir[di].activeLayer;
      SArcsLayer l;
      GetLayer(dir, li, l);
      if(!l.used || l.state != ARCS_LAYER_BUILDING)
      {
         LatchReconcile(dir, "BUILDING không có active layer hợp lệ");
         why = "BUILDING active layer invalid";
         return false;
      }
      int key = Recovery_CycleKey(dir);
      exec.ReconcileCycle(key);
      if(exec.HasReconcileRequired(key))
      {
         LatchReconcile(dir, "execution journal yêu cầu reconcile khi mở Hedge");
         why = "execution reconcile required";
         return false;
      }
      long live = Recovery_ArcsLayerUnits(dir, l.generation, m_volumeStep);
      if(live > l.targetUnits)
      {
         LatchReconcile(dir, "generation live volume vượt target");
         why = "generation over target";
         return false;
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
      if(!Recovery_ReadBundleVolumeMeta(_Symbol, meta, why)) return false;
      long remaining = l.targetUnits - live;
      long child = Recovery_BundleNextChildUnits(remaining, meta.minUnits, meta.maxOrderUnits);
      if(child <= 0)
      {
         LatchReconcile(dir, "phần volume còn lại không thể tạo child hợp lệ");
         why = "invalid remaining bundle child";
         return false;
      }
      int hedgeDir = Recovery_HedgeDirection(dir);
      long existingDirectional = Recovery_DirectionalExposureUnits(_Symbol, hedgeDir, meta.volumeStep);
      if(!Recovery_VolumeLimitAllows(child, existingDirectional, meta.volumeLimitUnits) ||
         !Recovery_ChildMarginPreflight(_Symbol, hedgeDir, child, meta.volumeStep, why))
      {
         if(why == "") why = "broker volume/margin preflight chặn child ARCS";
         LatchReconcile(dir, why);
         return false;
      }
      double volume = Recovery_UnitsToVolume(child, meta.volumeStep);
      int childNo = 1;
      SArcsPosition pos[];
      childNo += Recovery_ArcsBuildLayerPositions(dir, l.generation, m_volumeStep, pos);
      string comment = "BDR|C=" + (string)key +
                       "|G=" + (string)l.generation +
                       "|B=" + (string)l.bundleId +
                       "|N=" + (string)childNo;
      if(!SaveBeforeMutation(why)) return false;
      if(!exec.OpenMarketOwned(hedgeDir, volume,
                               (long)RecoveryMagic_, key,
                               EXEC_CMD_RECOVERY_OPEN,
                               EXEC_RECONCILE_FAIL_CLOSED,
                               comment))
      {
         if(exec.HasReconcileRequired(key))
            LatchReconcile(dir, "outcome mở ARCS Hedge không xác định");
         else
            LatchReconcile(dir, "broker từ chối mở ARCS Hedge child");
         why = "ARCS Hedge child send failed";
         return false;
      }
      return true;
   }

   bool PrepareTp(const eRecoveryCoreDirection dir,
                  const EAContext &ctx,
                  string &why)
   {
      why = "";
      int di = Idx(dir);
      int li = m_dir[di].activeLayer;
      SArcsLayer l;
      GetLayer(dir, li, l);
      if(!l.used || l.state != ARCS_LAYER_ACTIVE) return false;
      SArcsPosition pos[];
      SArcsLayerSnapshot snap;
      if(!Recovery_ArcsLayerSnapshot(dir, l.generation, m_volumeStep,
                                     m_tickSize, pos, snap, why))
      {
         LatchReconcile(dir, why);
         return false;
      }
      l.openedUnits = snap.units;
      l.remainingUnits = snap.units;
      l.weightedEntry = snap.weightedEntry;
      l.netBE = snap.netBE;
      if(!Recovery_VirtualHedgeTpHit(dir, snap.netBE,
                                     ctx.bid, ctx.ask,
                                     m_tpDistancePrice))
      {
         PutLayer(dir, li, l);
         why = "TP Hedge ảo chưa đạt";
         return false;
      }
      SRecoveryBundleVolumeMeta meta;
      if(!Recovery_ReadBundleVolumeMeta(_Symbol, meta, why)) return false;
      long target = Recovery_PartialCloseTargetUnits(snap.units,
                                                      HedgePartialClosePercent_,
                                                      meta.minUnits);
      if(target <= 0)
      {
         why = "Tỷ lệ chốt Hedge không thực thi được trên volume grid broker";
         LatchReconcile(dir, why);
         return false;
      }
      l.state = ARCS_LAYER_TP_PENDING;
      l.tpBaselineUnits = snap.units;
      l.tpTargetCloseUnits = target;
      l.tpObservedCloseUnits = 0;
      l.fundingClosedUnits = 0;
      l.tpTriggerPrice = dir == recovery_CORE_BUY ? ctx.ask : ctx.bid;
      PutLayer(dir, li, l);
      m_dir[di].phase = ARCS_TP_PENDING;
      m_dirty = true;
      return Save(why);
   }

   bool DriveTpPending(CExecutionLayer &exec,
                       const eRecoveryCoreDirection dir,
                       string &why)
   {
      why = "";
      int di = Idx(dir);
      int li = m_dir[di].activeLayer;
      SArcsLayer l;
      GetLayer(dir, li, l);
      if(!l.used || l.state != ARCS_LAYER_TP_PENDING)
      {
         LatchReconcile(dir, "TP_PENDING không có active generation");
         return false;
      }
      int key = Recovery_CycleKey(dir);
      exec.ReconcileCycle(key);
      if(exec.HasReconcileRequired(key))
      {
         LatchReconcile(dir, "partial close Hedge cần reconcile execution");
         return false;
      }
      long live = Recovery_ArcsLayerUnits(dir, l.generation, m_volumeStep);
      long closed = l.tpBaselineUnits - live;
      if(closed < 0 || closed > l.tpTargetCloseUnits)
      {
         LatchReconcile(dir, "broker-observed partial close vượt target generation");
         return false;
      }
      l.tpObservedCloseUnits = closed;
      l.remainingUnits = live;
      PutLayer(dir, li, l);
      if(closed == l.tpTargetCloseUnits)
      {
         if(l.fundingClosedUnits < closed || exec.HasPendingForCycle(key)) return true;
         if(l.fundingClosedUnits > closed)
         {
            LatchReconcile(dir, "realized funding units vượt partial-close target");
            return false;
         }
         m_dir[di].phase = ARCS_CORE_FUNDING;
         m_dirty = true;
         return Save(why);
      }
      if(exec.HasPendingForCycle(key)) return true;

      SArcsPosition positions[];
      SArcsLayerSnapshot snap;
      if(!Recovery_ArcsLayerSnapshot(dir, l.generation, m_volumeStep,
                                     m_tickSize, positions, snap, why)) return false;
      SRecoveryCloseCandidate c[];
      ArrayResize(c, ArraySize(positions));
      for(int i = 0; i < ArraySize(positions); i++)
      {
         c[i].ticket = positions[i].ticket;
         c[i].openTime = positions[i].openTime;
         c[i].units = positions[i].units;
         c[i].floatingCash = positions[i].floatingCash;
      }
      SRecoveryBundleVolumeMeta meta;
      if(!Recovery_ReadBundleVolumeMeta(_Symbol, meta, why)) return false;
      SRecoveryCloseAction plan[];
      long remainingClose = l.tpTargetCloseUnits - closed;
      if(!Recovery_BuildHedgeClosePlan(c, remainingClose, meta.minUnits, plan, why))
      {
         LatchReconcile(dir, why);
         return false;
      }
      if(!SaveBeforeMutation(why)) return false;
      double volume = Recovery_UnitsToVolume(plan[0].units, meta.volumeStep);
      if(!exec.ClosePositionVolumeOwned(plan[0].ticket, volume,
                                        (long)RecoveryMagic_, key,
                                        EXEC_CMD_RECOVERY_CLOSE,
                                        EXEC_RECONCILE_FAIL_CLOSED))
      {
         if(exec.HasReconcileRequired(key)) LatchReconcile(dir, "partial close Hedge outcome ambiguous");
         else LatchReconcile(dir, "partial close Hedge bị broker từ chối");
         return false;
      }
      return true;
   }

   bool DriveCoreFunding(CExecutionLayer &exec,
                         const eRecoveryCoreDirection dir,
                         string &why)
   {
      why = "";
      int di = Idx(dir);
      int li = m_dir[di].activeLayer;
      int key = Recovery_CycleKey(dir);
      exec.ReconcileCycle(key);
      if(exec.HasReconcileRequired(key))
      {
         LatchReconcile(dir, "Core funding execution cần reconcile");
         return false;
      }
      if(exec.HasPendingForCycle(key)) return true;

      SRecoveryCloseCandidate core[];
      Recovery_ArcsBuildCoreCloseCandidates(dir, m_volumeStep, core);
      SRecoveryBundleVolumeMeta meta;
      if(!Recovery_ReadBundleVolumeMeta(_Symbol, meta, why)) return false;
      SRecoveryCloseAction plan[];
      double estimated = 0.0;
      string planWhy = "";
      if(!Recovery_BuildCoreClosePlan(core, CoreCloseMode_,
                                      m_dir[di].availableCredit,
                                      meta.minUnits, plan, estimated, planWhy))
      {
         SArcsLayer l;
         GetLayer(dir, li, l);
         l.state = l.remainingUnits > 0 ? ARCS_LAYER_LOCK_PENDING : ARCS_LAYER_CLOSED;
         PutLayer(dir, li, l);
         m_dir[di].phase = ARCS_LOCK_PENDING;
         m_dirty = true;
         why = planWhy;
         return Save(planWhy);
      }
      if(!SaveBeforeMutation(why)) return false;
      double volume = Recovery_UnitsToVolume(plan[0].units, meta.volumeStep);
      if(!exec.ClosePositionVolumeOwned(plan[0].ticket, volume,
                                        (long)Magic, key,
                                        EXEC_CMD_RECOVERY_CLOSE,
                                        EXEC_RECONCILE_FAIL_CLOSED))
      {
         if(exec.HasReconcileRequired(key)) LatchReconcile(dir, "Core close funding outcome ambiguous");
         else LatchReconcile(dir, "Core close funding bị broker từ chối");
         return false;
      }
      return true;
   }

   bool AfterLayerLocked(const eRecoveryCoreDirection dir,
                         const datetime now,
                         string &why)
   {
      why = "";
      int di = Idx(dir);
      long core = Recovery_ArcsCoreUnits(dir, m_volumeStep);
      long hedge = Recovery_ArcsTotalHedgeUnits(dir, m_volumeStep);
      if(EnableGlobalHedgeSL_ && hedge > 0 &&
         m_dir[di].generationCount >= GlobalSLAfterGenerations_)
      {
         m_dir[di].phase = ARCS_GLOBAL_PROTECT;
         m_dirty = true;
         return Save(why);
      }
      if(core <= 0)
      {
         m_dir[di].phase = hedge > 0 ? ARCS_LOCKED : ARCS_IDLE;
         m_dirty = true;
         return Save(why);
      }
      if(m_dir[di].generationCount >= MaxHedgeGenerations_)
      {
         m_dir[di].phase = ARCS_LOCKED;
         m_dirty = true;
         return Save(why);
      }
      if(!StartGeneration(dir, now, why))
      {
         if(RecoverySizingPolicy_ == HEDGE_CAN_BANG &&
            Recovery_T16NewGenerationUnitsPure(RecoverySizingPolicy_, core, hedge,
                                               HedgeVolumePercent_) <= 0)
         {
            m_dir[di].phase = ARCS_LOCKED;
            m_dirty = true;
            return Save(why);
         }
         return false;
      }
      return Save(why);
   }

   bool DriveLockPending(CExecutionLayer &exec,
                         const eRecoveryCoreDirection dir,
                         const EAContext &ctx,
                         string &why)
   {
      why = "";
      int di = Idx(dir);
      int li = m_dir[di].activeLayer;
      SArcsLayer l;
      GetLayer(dir, li, l);
      if(!l.used)
      {
         LatchReconcile(dir, "LOCK_PENDING không có active layer");
         return false;
      }
      long live = Recovery_ArcsLayerUnits(dir, l.generation, m_volumeStep);
      l.remainingUnits = live;
      if(live <= 0)
      {
         l.state = ARCS_LAYER_CLOSED;
         PutLayer(dir, li, l);
         m_dir[di].phase = ARCS_LOCKED;
         return AfterLayerLocked(dir, ctx.now, why);
      }

      SArcsPosition pos[];
      SArcsLayerSnapshot snap;
      if(!Recovery_ArcsLayerSnapshot(dir, l.generation, m_volumeStep,
                                     m_tickSize, pos, snap, why))
      {
         LatchReconcile(dir, why);
         return false;
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
         return false;
      }
      l.weightedEntry = snap.weightedEntry;
      l.netBE = snap.netBE;
      l.lockTargetPrice = target;
      PutLayer(dir, li, l);

      if(HedgeSLMode_ == SL_VIRTUAL)
      {
         if(!Recovery_T16VirtualSlArmingValidPure(dir, ctx.bid, ctx.ask, target))
         {
            why = "SL ảo dương chưa nằm đúng phía giá để arm";
            return false;
         }
         l.virtualSlArmed = true;
         l.virtualSlPrice = target;
         l.state = ARCS_LAYER_LOCKED;
         PutLayer(dir, li, l);
         m_dir[di].phase = ARCS_LOCKED;
         return AfterLayerLocked(dir, ctx.now, why);
      }

      int key = Recovery_CycleKey(dir);
      exec.ReconcileCycle(key);
      if(exec.HasReconcileRequired(key))
      {
         LatchReconcile(dir, "broker SL modify cần reconcile");
         return false;
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
         return AfterLayerLocked(dir, ctx.now, why);
      }
      int stops = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
      int freeze = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
      if(!Recovery_LockBrokerDistanceValidPure(dir, target,
                                               ctx.bid, ctx.ask, ctx.point,
                                               stops, freeze, m_tickSize))
      {
         why = "SL dương chưa đặt được do stops/freeze level broker";
         return false;
      }
      if(!SaveBeforeMutation(why)) return false;
      if(!exec.ModifySlTpOwned(pos[weak].ticket, target, pos[weak].tp,
                               (long)RecoveryMagic_, key,
                               EXEC_CMD_RECOVERY_MODIFY,
                               EXEC_RECONCILE_FAIL_CLOSED))
      {
         if(exec.HasReconcileRequired(key)) LatchReconcile(dir, "broker SL modify outcome ambiguous");
         else LatchReconcile(dir, "broker từ chối SL dương generation");
         return false;
      }
      return true;
   }

   bool ComputeGlobalTarget(const eRecoveryCoreDirection dir,
                            double &target,
                            string &why)
   {
      target = 0.0;
      why = "";
      bool found = false;
      for(int i = 0; i < BD_ARCS_MAX_LAYERS; i++)
      {
         SArcsLayer l;
         GetLayer(dir, i, l);
         if(!l.used) continue;
         long live = Recovery_ArcsLayerUnits(dir, l.generation, m_volumeStep);
         if(live <= 0) continue;
         SArcsPosition pos[];
         SArcsLayerSnapshot snap;
         string local = "";
         if(!Recovery_ArcsLayerSnapshot(dir, l.generation, m_volumeStep,
                                        m_tickSize, pos, snap, local))
         {
            why = local;
            return false;
         }
         double candidate = Recovery_LockTargetPricePure(dir,
                                                         snap.weightedEntry,
                                                         snap.netBE,
                                                         m_globalProfitPrice,
                                                         m_lockSafetyPrice,
                                                         m_tickSize,
                                                         _Digits);
         if(candidate <= 0.0)
         {
            why = "không tính được Global SL đảm bảo net-positive cho mọi layer";
            return false;
         }
         target = Recovery_T16GlobalSlFoldPure(dir, target, candidate);
         found = true;
      }
      return found && target > 0.0;
   }

   bool DriveGlobalProtect(CExecutionLayer &exec,
                           const eRecoveryCoreDirection dir,
                           const EAContext &ctx,
                           string &why)
   {
      why = "";
      int di = Idx(dir);
      long total = Recovery_ArcsTotalHedgeUnits(dir, m_volumeStep);
      if(total <= 0)
      {
         EnterTransition(dir, ctx.bid, ctx.ask);
         return Save(why);
      }
      double target = 0.0;
      if(!ComputeGlobalTarget(dir, target, why))
      {
         LatchReconcile(dir, why);
         return false;
      }
      m_dir[di].globalSlPrice = target;
      if(HedgeSLMode_ == SL_VIRTUAL)
      {
         if(!Recovery_T16VirtualSlArmingValidPure(dir, ctx.bid, ctx.ask, target))
         {
            why = "Global SL ảo chưa nằm đúng phía giá để arm";
            return false;
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
               l.virtualSlArmed = true;
               l.virtualSlPrice = target;
               PutLayer(dir, i, l);
            }
         }
         return Save(why);
      }

      int key = Recovery_CycleKey(dir);
      exec.ReconcileCycle(key);
      if(exec.HasReconcileRequired(key))
      {
         LatchReconcile(dir, "Global SL broker modify cần reconcile");
         return false;
      }
      if(exec.HasPendingForCycle(key)) return true;

      int stops = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
      int freeze = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
      if(!Recovery_LockBrokerDistanceValidPure(dir, target,
                                               ctx.bid, ctx.ask, ctx.point,
                                               stops, freeze, m_tickSize))
      {
         why = "Global SL broker chưa đặt được do stops/freeze level";
         return false;
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
         if(!SaveBeforeMutation(why)) return false;
         if(!exec.ModifySlTpOwned(ticket, target, tp,
                                  (long)RecoveryMagic_, key,
                                  EXEC_CMD_RECOVERY_MODIFY,
                                  EXEC_RECONCILE_FAIL_CLOSED))
         {
            if(exec.HasReconcileRequired(key)) LatchReconcile(dir, "Global SL modify outcome ambiguous");
            else LatchReconcile(dir, "broker từ chối Global SL");
            return false;
         }
         return true;
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
      return Save(why);
   }

   bool CloseOneLayerPosition(CExecutionLayer &exec,
                              const eRecoveryCoreDirection dir,
                              const int generation,
                              string &why)
   {
      SArcsPosition pos[];
      Recovery_ArcsBuildLayerPositions(dir, generation, m_volumeStep, pos);
      if(ArraySize(pos) <= 0) return false;
      int key = Recovery_CycleKey(dir);
      if(exec.HasPendingForCycle(key)) return true;
      if(!SaveBeforeMutation(why)) return false;
      return exec.ClosePositionVolumeOwned(pos[0].ticket, pos[0].lots,
                                           (long)RecoveryMagic_, key,
                                           EXEC_CMD_RECOVERY_CLOSE,
                                           EXEC_RECONCILE_FAIL_CLOSED);
   }

   bool DriveLayerVirtualStops(CExecutionLayer &exec,
                               const eRecoveryCoreDirection dir,
                               const EAContext &ctx,
                               string &why)
   {
      if(HedgeSLMode_ != SL_VIRTUAL) return false;
      int di = Idx(dir);
      if(m_dir[di].phase == ARCS_GLOBAL_ACTIVE ||
         m_dir[di].phase == ARCS_GLOBAL_CLOSING) return false;
      for(int i = 0; i < BD_ARCS_MAX_LAYERS; i++)
      {
         SArcsLayer l;
         GetLayer(dir, i, l);
         if(!l.used || l.state != ARCS_LAYER_LOCKED || !l.virtualSlArmed) continue;
         long live = Recovery_ArcsLayerUnits(dir, l.generation, m_volumeStep);
         if(live <= 0)
         {
            l.remainingUnits = 0;
            l.state = ARCS_LAYER_CLOSED;
            PutLayer(dir, i, l);
            continue;
         }
         if(!Recovery_T16VirtualSlHitPure(dir, ctx.bid, ctx.ask, l.virtualSlPrice)) continue;
         if(CloseOneLayerPosition(exec, dir, l.generation, why)) return true;
         if(exec.HasReconcileRequired(Recovery_CycleKey(dir)))
            LatchReconcile(dir, "virtual SL layer close outcome ambiguous");
         return false;
      }
      return false;
   }

   void EnterTransition(const eRecoveryCoreDirection dir,
                        const double bid,
                        const double ask)
   {
      int di = Idx(dir);
      double ref = m_dir[di].globalSlPrice;
      if(ref <= 0.0) ref = dir == recovery_CORE_BUY ? ask : bid;
      m_dir[di].transitionReferencePrice = ref;
      m_dir[di].globalSlArmed = false;
      m_dir[di].phase = ARCS_TRANSITION;
      m_dir[di].activeLayer = -1;
      m_dirty = true;
   }

   bool DriveGlobalActive(CExecutionLayer &exec,
                          const eRecoveryCoreDirection dir,
                          const EAContext &ctx,
                          string &why)
   {
      int di = Idx(dir);
      long total = Recovery_ArcsTotalHedgeUnits(dir, m_volumeStep);
      if(total <= 0)
      {
         EnterTransition(dir, ctx.bid, ctx.ask);
         return Save(why);
      }
      if(HedgeSLMode_ == SL_BROKER) return false;
      if(!m_dir[di].globalSlArmed ||
         !Recovery_T16VirtualSlHitPure(dir, ctx.bid, ctx.ask, m_dir[di].globalSlPrice))
         return false;
      m_dir[di].phase = ARCS_GLOBAL_CLOSING;
      m_dirty = true;
      return Save(why);
   }

   bool DriveGlobalClosing(CExecutionLayer &exec,
                           const eRecoveryCoreDirection dir,
                           const EAContext &ctx,
                           string &why)
   {
      int key = Recovery_CycleKey(dir);
      exec.ReconcileCycle(key);
      if(exec.HasReconcileRequired(key))
      {
         LatchReconcile(dir, "Global virtual close cần reconcile");
         return false;
      }
      if(exec.HasPendingForCycle(key)) return true;
      long wanted = Recovery_ArcsHedgeType(dir);
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol ||
            PositionGetInteger(POSITION_MAGIC) != (long)RecoveryMagic_ ||
            PositionGetInteger(POSITION_TYPE) != wanted)
            continue;
         double volume = PositionGetDouble(POSITION_VOLUME);
         if(!SaveBeforeMutation(why)) return false;
         if(!exec.ClosePositionVolumeOwned(ticket, volume,
                                           (long)RecoveryMagic_, key,
                                           EXEC_CMD_RECOVERY_CLOSE,
                                           EXEC_RECONCILE_FAIL_CLOSED))
         {
            if(exec.HasReconcileRequired(key)) LatchReconcile(dir, "Global virtual close outcome ambiguous");
            else LatchReconcile(dir, "Global virtual close bị broker từ chối");
            return false;
         }
         return true;
      }
      EnterTransition(dir, ctx.bid, ctx.ask);
      return Save(why);
   }

   void ResetForReentry(const eRecoveryCoreDirection dir)
   {
      int di = Idx(dir);
      double ref = m_dir[di].transitionReferencePrice;
      ulong lastDeal = m_dir[di].lastDealTicket;
      long lastMsc = m_dir[di].lastDealTimeMsc;
      Recovery_ArcsDirectionReset(m_dir[di]);
      m_dir[di].phase = ARCS_LOCKED; // transient parent for immediate StartGeneration
      m_dir[di].transitionReferencePrice = ref;
      m_dir[di].lastDealTicket = lastDeal;
      m_dir[di].lastDealTimeMsc = lastMsc;
      Recovery_ArcsPendingReset(m_pending[di]);
      ResetLayers(dir);
      m_dirty = true;
   }

   bool DriveTransition(const eRecoveryCoreDirection dir,
                        const EAContext &ctx,
                        string &why)
   {
      int di = Idx(dir);
      if(Recovery_ArcsCoreUnits(dir, m_volumeStep) <= 0)
      {
         ResetDirection(dir);
         return Save(why);
      }
      long refTicks = Recovery_PriceToTicksPure(m_dir[di].transitionReferencePrice, m_tickSize);
      long bidTicks = Recovery_PriceToTicksPure(ctx.bid, m_tickSize);
      long askTicks = Recovery_PriceToTicksPure(ctx.ask, m_tickSize);
      if(refTicks <= 0) return false;
      if(dir == recovery_CORE_BUY)
      {
         if(bidTicks <= refTicks - m_reentryBufferTicks)
         {
            ResetForReentry(dir);
            if(!StartGeneration(dir, ctx.now, why)) return false;
            return Save(why);
         }
         if(askTicks >= refTicks + m_reentryBufferTicks)
         {
            m_dir[di].phase = ARCS_REVERSAL_HOLD;
            m_dirty = true;
            return Save(why);
         }
      }
      else
      {
         if(askTicks >= refTicks + m_reentryBufferTicks)
         {
            ResetForReentry(dir);
            if(!StartGeneration(dir, ctx.now, why)) return false;
            return Save(why);
         }
         if(bidTicks <= refTicks - m_reentryBufferTicks)
         {
            m_dir[di].phase = ARCS_REVERSAL_HOLD;
            m_dirty = true;
            return Save(why);
         }
      }
      return false;
   }

   bool DriveDirection(CExecutionLayer &exec,
                       const eRecoveryCoreDirection dir,
                       const EAContext &ctx,
                       string &why)
   {
      why = "";
      int di = Idx(dir);
      if(m_dir[di].phase == ARCS_RECONCILE) return false;
      if(DriveLayerVirtualStops(exec, dir, ctx, why)) return true;

      switch(m_dir[di].phase)
      {
         case ARCS_IDLE:
         case ARCS_REVERSAL_HOLD:
            return false;
         case ARCS_ARMED:
            if(!InitialGapHit(dir, ctx)) return false;
            if(!StartGeneration(dir, ctx.now, why)) return false;
            return Save(why);
         case ARCS_BUILDING:
            return DriveBuilding(exec, dir, ctx.now, why);
         case ARCS_ACTIVE:
            return PrepareTp(dir, ctx, why);
         case ARCS_TP_PENDING:
            return DriveTpPending(exec, dir, why);
         case ARCS_CORE_FUNDING:
            return DriveCoreFunding(exec, dir, why);
         case ARCS_LOCK_PENDING:
            return DriveLockPending(exec, dir, ctx, why);
         case ARCS_LOCKED:
         {
            int li = m_dir[di].activeLayer;
            SArcsLayer l;
            GetLayer(dir, li, l);
            if(li >= 0 && l.used && l.state == ARCS_LAYER_LOCKED)
               return AfterLayerLocked(dir, ctx.now, why);
            if(Recovery_ArcsTotalHedgeUnits(dir, m_volumeStep) <= 0)
            {
               m_dir[di].phase = ARCS_REVERSAL_HOLD;
               m_dirty = true;
               return Save(why);
            }
            return false;
         }
         case ARCS_GLOBAL_PROTECT:
            return DriveGlobalProtect(exec, dir, ctx, why);
         case ARCS_GLOBAL_ACTIVE:
            return DriveGlobalActive(exec, dir, ctx, why);
         case ARCS_GLOBAL_CLOSING:
            return DriveGlobalClosing(exec, dir, ctx, why);
         case ARCS_TRANSITION:
            return DriveTransition(dir, ctx, why);
         case ARCS_RECONCILE:
            return false;
      }
      return false;
   }

public:
   CRecoveryArcsStack(void)
   {
      m_initialized = false;
      m_ready = false;
      m_persistLoaded = false;
      m_persistMissing = false;
      m_persistenceBlocked = false;
      m_dirty = false;
      m_saveSequence = 0;
      m_volumeStep = 0.0;
      m_tickSize = 0.0;
      m_isGold = false;
      m_initialGapTicks = 0;
      m_tpDistancePrice = 0.0;
      m_lockProfitPrice = 0.0;
      m_lockSafetyPrice = 0.0;
      m_globalProfitPrice = 0.0;
      m_reentryBufferTicks = 0;
      m_startupFault = "";
      ArrayResize(m_buyLayers, BD_ARCS_MAX_LAYERS);
      ArrayResize(m_sellLayers, BD_ARCS_MAX_LAYERS);
      Recovery_ArcsDirectionReset(m_dir[0]);
      Recovery_ArcsDirectionReset(m_dir[1]);
      Recovery_ArcsPendingReset(m_pending[0]);
      Recovery_ArcsPendingReset(m_pending[1]);
      ResetLayers(recovery_CORE_BUY);
      ResetLayers(recovery_CORE_SELL);
   }

   bool Init()
   {
      string why = "";
      if(!Recovery_T16ValidateConfig(why))
      {
         Log_Error("Recovery", "T16 config invalid: " + why);
         return false;
      }
      m_volumeStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      m_tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      m_isGold = Sym_IsGold();
      if(m_volumeStep <= 0.0 || m_tickSize <= 0.0)
      {
         Log_Error("Recovery", "T16 invalid symbol volume-step/tick-size");
         return false;
      }
      m_initialGapTicks = Recovery_PipsToTicksPure(HedgeGapPips_, m_isGold,
                                                   _Point, _Digits, m_tickSize);
      m_tpDistancePrice = Recovery_PipsToPricePure(HedgeTPPips_, m_isGold,
                                                   _Point, _Digits);
      m_lockProfitPrice = Recovery_PipsToPricePure(HedgeLockNetProfitPips_, m_isGold,
                                                   _Point, _Digits);
      m_lockSafetyPrice = Recovery_PipsToPricePure(HedgeLockSafetyBufferPips_, m_isGold,
                                                   _Point, _Digits);
      m_globalProfitPrice = Recovery_PipsToPricePure(GlobalHedgeSLNetProfitPips_, m_isGold,
                                                     _Point, _Digits);
      m_reentryBufferTicks = Recovery_PipsToTicksPure(RecoveryReentryBufferPips_, m_isGold,
                                                      _Point, _Digits, m_tickSize);
      m_persistence.Init(_Symbol, AccountInfoInteger(ACCOUNT_LOGIN),
                         (long)Magic, (long)RecoveryMagic_);
      m_ready = RecoveryMode_ != recovery_ACTIVE;
      m_persistLoaded = false;
      m_persistMissing = false;
      m_persistenceBlocked = false;
      m_dirty = false;
      m_saveSequence = 0;
      m_startupFault = "";
      Recovery_ArcsDirectionReset(m_dir[0]);
      Recovery_ArcsDirectionReset(m_dir[1]);
      Recovery_ArcsPendingReset(m_pending[0]);
      Recovery_ArcsPendingReset(m_pending[1]);
      ResetLayers(recovery_CORE_BUY);
      ResetLayers(recovery_CORE_SELL);

      if(RecoveryMode_ == recovery_ACTIVE)
      {
         SArcsPersistIdentity identity;
         SArcsLayer buy[];
         SArcsLayer sell[];
         string loadWhy = "";
         eArcsPersistStatus st = m_persistence.Load(identity,
                                                    m_dir[0], m_dir[1],
                                                    m_pending[0], m_pending[1],
                                                    buy, sell, loadWhy);
         if(st == ARCS_PERSIST_OK)
         {
            ArrayResize(m_buyLayers, BD_ARCS_MAX_LAYERS);
            ArrayResize(m_sellLayers, BD_ARCS_MAX_LAYERS);
            for(int i = 0; i < BD_ARCS_MAX_LAYERS; i++)
            {
               m_buyLayers[i] = buy[i];
               m_sellLayers[i] = sell[i];
            }
            m_saveSequence = identity.saveSequence;
            m_persistLoaded = true;
         }
         else if(st == ARCS_PERSIST_NOT_FOUND)
            m_persistMissing = true;
         else
         {
            m_persistenceBlocked = true;
            m_startupFault = loadWhy;
         }
      }
      m_initialized = true;
      return true;
   }

   bool StartupReconcile(CExecutionLayer &exec, string &why)
   {
      why = "";
      if(RecoveryMode_ != recovery_ACTIVE) return true;
      if(!m_initialized) { why = "T16 ARCS chưa Init"; return false; }
      if(m_persistenceBlocked)
      {
         why = m_startupFault == "" ? "ARCS persistence corrupt/mismatch" : m_startupFault;
         m_ready = false;
         return false;
      }
      if(m_persistMissing)
      {
         if(Recovery_ArcsTotalHedgeUnits(recovery_CORE_BUY, m_volumeStep) > 0 ||
            Recovery_ArcsTotalHedgeUnits(recovery_CORE_SELL, m_volumeStep) > 0)
         {
            why = "không có persistence ARCS nhưng broker đang có RecoveryMagic exposure";
            m_ready = false;
            return false;
         }
         m_ready = true;
         m_dirty = true;
         if(!Save(why)) return false;
         Log_Info("Recovery", "T16 ARCS startup fresh/clean — ACTIVE enabled");
         return true;
      }

      exec.ReconcileCycle(Recovery_CycleKey(recovery_CORE_BUY));
      exec.ReconcileCycle(Recovery_CycleKey(recovery_CORE_SELL));
      if(exec.HasReconcileRequired(Recovery_CycleKey(recovery_CORE_BUY)) ||
         exec.HasReconcileRequired(Recovery_CycleKey(recovery_CORE_SELL)))
      {
         why = "execution journal yêu cầu reconcile khi startup ARCS";
         m_ready = false;
         return false;
      }
      if(!ReplayAfterCursor(recovery_CORE_BUY, why) ||
         !ReplayAfterCursor(recovery_CORE_SELL, why) ||
         !ValidateLiveBook(recovery_CORE_BUY, why) ||
         !ValidateLiveBook(recovery_CORE_SELL, why))
      {
         m_ready = false;
         return false;
      }
      if(m_pending[0].active || m_pending[1].active)
      {
         why = "startup ARCS còn durable external command chưa resolve";
         m_ready = false;
         return false;
      }
      m_ready = true;
      m_dirty = true;
      if(!Save(why)) return false;
      Log_Info("Recovery", "T16 ARCS startup reconciliation complete; layer ownership + SL state durable");
      return true;
   }

   bool ActiveReady() const
   {
      return RecoveryMode_ != recovery_ACTIVE || m_ready;
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
         if(core <= 0 && hedge <= 0 &&
            (m_dir[d].phase == ARCS_IDLE || m_dir[d].phase == ARCS_REVERSAL_HOLD))
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
      if(RecoveryMode_ != recovery_ACTIVE || !m_ready) return false;
      string w = "";
      if(DriveDirection(exec, recovery_CORE_BUY, ctx, w))
      {
         why = w;
         return true;
      }
      if(w != "") why = w;
      w = "";
      if(DriveDirection(exec, recovery_CORE_SELL, ctx, w))
      {
         if(w != "") why = why == "" ? w : why + "; " + w;
         return true;
      }
      if(w != "") why = why == "" ? w : why + "; " + w;
      if(m_dirty) FlushPersistence();
      return false;
   }

   void OnTradeTransaction(const MqlTradeTransaction &trans)
   {
      if(!m_initialized || RecoveryMode_ != recovery_ACTIVE ||
         trans.type != TRADE_TRANSACTION_DEAL_ADD || trans.deal == 0 ||
         trans.symbol != _Symbol || !HistoryDealSelect(trans.deal)) return;
      ApplyCloseDeal(trans.deal);
      string why = "";
      if(m_dirty && !Save(why)) Log_Error("Recovery", "T16 deal persistence failed: " + why);
   }

   bool FlushPersistence()
   {
      if(RecoveryMode_ != recovery_ACTIVE || !m_dirty) return true;
      string why = "";
      if(!Save(why))
      {
         Log_Error("Recovery", "T16 durable state flush failed: " + why);
         return false;
      }
      return true;
   }

   void RecordDealCursor(const ulong deal)
   {
      if(deal == 0 || !HistoryDealSelect(deal)) return;
      long owner = ResolveClosedOwnerMagic(deal);
      if(!HistoryDealSelect(deal)) return;
      long type = HistoryDealGetInteger(deal, DEAL_TYPE);
      bool mapped = false;
      eRecoveryCoreDirection dir = DirectionForClose(owner, type, mapped);
      if(mapped) TrackCursor(dir, deal);
   }

   void GetCycle(const eRecoveryCoreDirection dir, SRecoveryCycle &out) const
   {
      ZeroMemory(out);
      int di = Idx(dir);
      out.direction = dir;
      out.cycleKey = Recovery_CycleKey(dir);
      out.cycleSerial = 1;
      out.state = Recovery_ArcsPublicState(m_dir[di].phase);
      SArcsPosition core[];
      out.coreCount = Recovery_ArcsBuildCore(dir, m_volumeStep, core);
      long coreUnits = Recovery_ArcsCoreUnits(dir, m_volumeStep);
      long hedgeUnits = Recovery_ArcsTotalHedgeUnits(dir, m_volumeStep);
      out.coreLots = Recovery_UnitsToVolume(coreUnits, m_volumeStep);
      out.activeHedgeLots = Recovery_UnitsToVolume(hedgeUnits, m_volumeStep);
      out.coveragePercent = coreUnits > 0 ? (double)hedgeUnits / (double)coreUnits * 100.0 : 0.0;
      out.armed = m_dir[di].armed;
      out.anchorPosition = m_dir[di].anchorPosition;
      out.anchorPrice = m_dir[di].anchorPrice;
      out.anchorTicks = m_dir[di].anchorTicks;
      out.anchorTime = m_dir[di].anchorTime;
      out.hedgeGeneration = m_dir[di].generationCount;
      out.hedgeNetBE = 0.0;
   }

   long NextGenerationUnits(const eRecoveryCoreDirection dir) const
   {
      long core = Recovery_ArcsCoreUnits(dir, m_volumeStep);
      long hedge = Recovery_ArcsTotalHedgeUnits(dir, m_volumeStep);
      return Recovery_T16NewGenerationUnitsPure(RecoverySizingPolicy_, core, hedge,
                                                HedgeVolumePercent_);
   }

   long RehedgeAnchorTicks(const eRecoveryCoreDirection dir) const
   {
      return m_dir[Idx(dir)].anchorTicks;
   }

   double LockTargetPrice(const eRecoveryCoreDirection dir) const
   {
      int di = Idx(dir);
      if(m_dir[di].globalSlArmed && m_dir[di].globalSlPrice > 0.0)
         return m_dir[di].globalSlPrice;
      int li = m_dir[di].activeLayer;
      SArcsLayer l;
      GetLayer(dir, li, l);
      return l.lockTargetPrice;
   }

   void GetT5Runtime(const eRecoveryCoreDirection dir,
                     SRecoveryT5CycleRuntime &out) const
   {
      Recovery_T5RuntimeInit(out);
      int di = Idx(dir);
      int li = m_dir[di].activeLayer;
      SArcsLayer l;
      GetLayer(dir, li, l);
      out.tpLatched = l.state == ARCS_LAYER_TP_PENDING;
      out.hedgeCloseBaselineUnits = l.tpBaselineUnits;
      out.hedgeCloseTargetUnits = l.tpTargetCloseUnits;
      out.hedgeCloseObservedUnits = l.tpObservedCloseUnits;
      out.hedgeNetBE = l.netBE;
      out.tpTriggerPrice = l.tpTriggerPrice;
      out.ledger.hedgeNetCash = m_dir[di].hedgeFundingCash;
      out.ledger.coreLossSpent = m_dir[di].coreLossSpent;
      out.ledger.availableCredit = m_dir[di].availableCredit;
      out.ledger.hedgeRealizedCloseUnits = l.fundingClosedUnits;
      out.ledger.deficit = m_dir[di].coreLossSpent >
                           MathMax(0.0, m_dir[di].hedgeFundingCash) + 1e-8;
   }

   bool HasExposure(const eRecoveryCoreDirection dir) const
   {
      return Recovery_ArcsTotalHedgeUnits(dir, m_volumeStep) > 0;
   }

   bool HasAnyExposure() const
   {
      return HasExposure(recovery_CORE_BUY) || HasExposure(recovery_CORE_SELL);
   }

   bool ExpectedBrokerSlDeal(const ulong deal)
   {
      if(HedgeSLMode_ != SL_BROKER || deal == 0 || !HistoryDealSelect(deal)) return false;
      if(HistoryDealGetInteger(deal, DEAL_REASON) != DEAL_REASON_SL) return false;
      ulong posId = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
      int generation = Recovery_ArcsGenerationFromPositionHistory(posId);
      if(generation < 1) return false;
      long type = HistoryDealGetInteger(deal, DEAL_TYPE);
      eRecoveryCoreDirection dir = type == DEAL_TYPE_BUY ? recovery_CORE_BUY : recovery_CORE_SELL;
      int li = FindLayerByGeneration(dir, generation);
      if(li < 0) return false;
      SArcsLayer l;
      GetLayer(dir, li, l);
      double programmed = HistoryDealGetDouble(deal, DEAL_SL);
      double target = m_dir[Idx(dir)].globalSlArmed ? m_dir[Idx(dir)].globalSlPrice
                                                    : l.lockTargetPrice;
      double tol = MathMax(2.0 * m_tickSize, _Point);
      return target > 0.0 && programmed > 0.0 && MathAbs(programmed - target) <= tol;
   }

   void LatchExternalMutation(const eRecoveryCoreDirection dir,
                              const string reason)
   {
      LatchReconcile(dir, reason);
      string why = "";
      Save(why);
   }

   bool FinalizeConfirmedGlobalFlatten(CExecutionLayer &exec,
                                       const datetime now,
                                       string &why)
   {
      why = "";
      if(PositionsTotal() != 0 || exec.HasPending())
      {
         why = "global flatten ARCS cần account flat + execution journal quiet";
         return false;
      }
      ResetDirection(recovery_CORE_BUY);
      ResetDirection(recovery_CORE_SELL);
      m_ready = true;
      m_persistenceBlocked = false;
      return Save(why);
   }

   bool FinalizeConfirmedSideMutation(CExecutionLayer &exec,
                                      const eRecoveryCoreDirection dir,
                                      const datetime now,
                                      string &why)
   {
      why = "";
      int key = Recovery_CycleKey(dir);
      exec.ReconcileCycle(key);
      if(exec.HasPendingForCycle(key) || exec.HasReconcileRequired(key))
      {
         why = "side mutation ARCS execution chưa quiet/reconciled";
         return false;
      }
      long core = Recovery_ArcsCoreUnits(dir, m_volumeStep);
      long hedge = Recovery_ArcsTotalHedgeUnits(dir, m_volumeStep);
      if(core == 0 && hedge == 0)
      {
         ResetDirection(dir);
         m_ready = true;
         return Save(why);
      }
      // Intentional stacked over-hedge is valid. Unknown partial topology
      // changes are not auto-trimmed; they require explicit reconciliation.
      why = "partial side mutation trong ARCS stacked cần explicit reconcile";
      LatchReconcile(dir, why);
      return false;
   }

   bool ArmExternalPending(const eRecoveryCoreDirection dir,
                           const eExecCommandType commandType,
                           const long ownerMagic,
                           const ulong ticket,
                           const long targetUnits,
                           const long observedUnitsBefore,
                           const double targetPrice,
                           string &why)
   {
      why = "";
      int i = Idx(dir);
      if(m_pending[i].active)
      {
         why = "ARCS durable external command đã tồn tại";
         return false;
      }
      m_pending[i].active = true;
      m_pending[i].commandType = commandType;
      m_pending[i].ownerMagic = ownerMagic;
      m_pending[i].ticket = ticket;
      m_pending[i].targetUnits = targetUnits;
      m_pending[i].observedUnitsBefore = observedUnitsBefore;
      m_pending[i].targetPrice = targetPrice;
      m_pending[i].startedAt = TimeCurrent();
      m_dirty = true;
      return Save(why);
   }

   bool CancelExternalPending(const eRecoveryCoreDirection dir)
   {
      Recovery_ArcsPendingReset(m_pending[Idx(dir)]);
      m_dirty = true;
      string why = "";
      return Save(why);
   }

   bool HasExternalPending(const eRecoveryCoreDirection dir) const
   {
      return m_pending[Idx(dir)].active;
   }

   bool ResolveExternalPending(CExecutionLayer &exec,
                               const eRecoveryCoreDirection dir,
                               string &why)
   {
      why = "";
      int i = Idx(dir);
      if(!m_pending[i].active) return true;
      int key = Recovery_CycleKey(dir);
      exec.ReconcileCycle(key);
      if(exec.HasReconcileRequired(key))
      {
         why = "external ARCS command outcome ambiguous";
         return false;
      }
      if(exec.HasPendingForCycle(key)) return true;
      SArcsExternalPending p = m_pending[i];
      bool resolved = false;
      if(p.commandType == EXEC_CMD_RECOVERY_CLOSE)
      {
         long current = TotalOwnerUnits(dir, p.ownerMagic);
         long expected = p.observedUnitsBefore > p.targetUnits ?
                         p.observedUnitsBefore - p.targetUnits : 0;
         resolved = current <= expected;
      }
      else if(p.commandType == EXEC_CMD_RECOVERY_MODIFY && p.ticket != 0 &&
              PositionSelectByTicket(p.ticket))
      {
         double sl = PositionGetDouble(POSITION_SL);
         resolved = MathAbs(sl - p.targetPrice) <= MathMax(m_tickSize, _Point);
      }
      if(!resolved)
      {
         why = "external ARCS durable command không có broker effect xác nhận";
         return false;
      }
      return CancelExternalPending(dir);
   }

   int AuditStoredCount() const { return 0; }
   int AuditTotalCount() const { return 0; }
};

#endif // BD_RECOVERY_ARCS_STACK_MQH
