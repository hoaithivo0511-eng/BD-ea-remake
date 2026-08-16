//+------------------------------------------------------------------+
//| RecoveryEngine.mqh — T3 SHADOW + T4 bundle + T5/T6 mechanics    |
//| Invariants: SHADOW sends NO trade request and never blocks Core. |
//|             ACTIVE remains fail-closed until durable T9 wiring.  |
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_ENGINE_MQH
#define BD_RECOVERY_ENGINE_MQH

#include <BlackDragon/Types.mqh>
#include <BlackDragon/Logger.mqh>
#include <BlackDragon/ExecutionLayer.mqh>
#include "RecoveryRegistry.mqh"
#include "RecoveryExit.mqh"
#include "RecoveryLock.mqh"
#include "RecoveryPersistence.mqh"

#define BD_RECOVERY_T5_SEEN_DEALS 128

struct SRecoveryCorePositionSnapshot
{
   ulong    ticket;
   datetime openTime;
   double   openPrice;
   double   lots;
   double   floatingCash;
};

class CRecoveryEngine
{
private:
   CRecoveryRegistry          m_registry;
   SRecoveryFoundationConfig  m_cfg;
   SRecoveryT5CycleRuntime    m_t5[2];
   int                        m_t5CycleSerial[2];
   long                       m_t5HedgeRealizedBaseline[2];
   double                     m_t6AnchorWeighted[2];
   long                       m_t6AnchorUnits[2];
   long                       m_t6RehedgeAnchorTicks[2];
   double                     m_t6LockTargetPrice[2];
   ulong                      m_seenDeals[BD_RECOVERY_T5_SEEN_DEALS];
   int                        m_seenWrite;
   int                        m_seenStored;
   bool                       m_initialized;
   double                     m_tickSize;
   double                     m_volumeStep;
   bool                       m_isGold;
   long                       m_gapTicks;
   double                     m_tpDistancePrice;
   double                     m_lockProfitDistancePrice;
   double                     m_lockSafetyBufferPrice;
   long                       m_rehedgeGapTicks;
   CRecoveryPersistence       m_persistence;
   SRecoveryPersistPending    m_pending[2];
   bool                       m_activeReady;
   bool                       m_persistLoaded;
   bool                       m_persistMissing;
   bool                       m_persistenceBlocked;
   bool                       m_dirty;
   long                       m_saveSequence;
   ulong                      m_lastDealTicket;
   long                       m_lastDealTimeMsc;
   string                     m_startupFaultReason;

   int DirIndex(const eRecoveryCoreDirection dir) const
   {
      return dir == recovery_CORE_BUY ? 0 : 1;
   }

   void ResetT6Cycle(const int idx)
   {
      if(idx < 0 || idx > 1) return;
      m_t5HedgeRealizedBaseline[idx] = 0;
      m_t6AnchorWeighted[idx] = 0.0;
      m_t6AnchorUnits[idx] = 0;
      m_t6RehedgeAnchorTicks[idx] = 0;
      m_t6LockTargetPrice[idx] = 0.0;
   }

   void EnsureT5Cycle(const eRecoveryCoreDirection dir)
   {
      int idx = DirIndex(dir);
      SRecoveryCycle cycle;
      m_registry.GetCycle(dir, cycle);
      if(m_t5CycleSerial[idx] == cycle.cycleSerial) return;
      Recovery_T5RuntimeInit(m_t5[idx]);
      ResetT6Cycle(idx);
      m_t5CycleSerial[idx] = cycle.cycleSerial;
   }

   bool DealSeen(const ulong deal) const
   {
      if(deal == 0) return true;
      for(int i = 0; i < m_seenStored; i++)
      {
         int slot = m_seenWrite - 1 - i;
         while(slot < 0) slot += BD_RECOVERY_T5_SEEN_DEALS;
         if(m_seenDeals[slot] == deal) return true;
      }
      return false;
   }

   void MarkDealSeen(const ulong deal)
   {
      if(deal == 0 || DealSeen(deal)) return;
      m_seenDeals[m_seenWrite] = deal;
      m_seenWrite = (m_seenWrite + 1) % BD_RECOVERY_T5_SEEN_DEALS;
      if(m_seenStored < BD_RECOVERY_T5_SEEN_DEALS) m_seenStored++;
   }

   void SortOldestFirst(SRecoveryCorePositionSnapshot &items[])
   {
      int n = ArraySize(items);
      for(int i = 1; i < n; i++)
      {
         SRecoveryCorePositionSnapshot key = items[i];
         int j = i - 1;
         while(j >= 0 &&
              (items[j].openTime > key.openTime ||
               (items[j].openTime == key.openTime && items[j].ticket > key.ticket)))
         {
            items[j + 1] = items[j];
            j--;
         }
         items[j + 1] = key;
      }
   }

   void BuildCoreSnapshots(SRecoveryCorePositionSnapshot &buyPos[],
                           SRecoveryCorePositionSnapshot &sellPos[],
                           double &buyLots, double &sellLots)
   {
      ArrayResize(buyPos, 0);
      ArrayResize(sellPos, 0);
      buyLots = 0.0;
      sellLots = 0.0;

      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         if(PositionGetInteger(POSITION_MAGIC) != (long)Magic) continue;

         long type = PositionGetInteger(POSITION_TYPE);
         if(type != POSITION_TYPE_BUY && type != POSITION_TYPE_SELL) continue;

         SRecoveryCorePositionSnapshot p;
         p.ticket       = ticket;
         p.openTime     = (datetime)PositionGetInteger(POSITION_TIME);
         p.openPrice    = PositionGetDouble(POSITION_PRICE_OPEN);
         p.lots         = PositionGetDouble(POSITION_VOLUME);
         p.floatingCash = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);

         if(type == POSITION_TYPE_BUY)
         {
            int n = ArraySize(buyPos);
            ArrayResize(buyPos, n + 1);
            buyPos[n] = p;
            buyLots += p.lots;
         }
         else
         {
            int n = ArraySize(sellPos);
            ArrayResize(sellPos, n + 1);
            sellPos[n] = p;
            sellLots += p.lots;
         }
      }

      SortOldestFirst(buyPos);
      SortOldestFirst(sellPos);
   }

   void BuildCoreCloseCandidates(const eRecoveryCoreDirection dir,
                                 SRecoveryCloseCandidate &out[])
   {
      ArrayResize(out, 0);
      long wanted = dir == recovery_CORE_BUY ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol ||
            PositionGetInteger(POSITION_MAGIC) != (long)Magic ||
            PositionGetInteger(POSITION_TYPE) != wanted)
            continue;

         long units = Recovery_VolumeToUnitsFloor(PositionGetDouble(POSITION_VOLUME), m_volumeStep);
         if(units <= 0) continue;
         SRecoveryCloseCandidate c;
         c.ticket       = ticket;
         c.openTime     = (datetime)PositionGetInteger(POSITION_TIME);
         c.units        = units;
         c.floatingCash = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
         int n = ArraySize(out);
         ArrayResize(out, n + 1);
         out[n] = c;
      }
   }

   double PositionEntryCosts(const ulong positionIdentifier) const
   {
      if(positionIdentifier == 0 || !HistorySelectByPosition(positionIdentifier)) return 0.0;
      double costs = 0.0;
      for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
      {
         ulong deal = HistoryDealGetTicket(i);
         if(deal == 0) continue;
         if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol ||
            HistoryDealGetInteger(deal, DEAL_MAGIC) != m_cfg.recoveryMagic)
            continue;
         long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
         if(entry != DEAL_ENTRY_IN && entry != DEAL_ENTRY_INOUT) continue;
         costs += HistoryDealGetDouble(deal, DEAL_COMMISSION)
                + HistoryDealGetDouble(deal, DEAL_FEE);
      }
      return costs;
   }

   bool BuildRecoveryHedgeSnapshot(const eRecoveryCoreDirection dir,
                                   SRecoveryCloseCandidate &out[],
                                   long &activeUnits,
                                   double &activeLots,
                                   double &netBE) const
   {
      ArrayResize(out, 0);
      activeUnits = 0;
      activeLots = 0.0;
      netBE = 0.0;
      if(m_volumeStep <= 0.0 || m_tickSize <= 0.0) return false;

      long wantedType = Recovery_HedgeDirection(dir) == 0 ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
      double weighted = 0.0;
      double signedCosts = 0.0;

      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol ||
            PositionGetInteger(POSITION_MAGIC) != m_cfg.recoveryMagic ||
            PositionGetInteger(POSITION_TYPE) != wantedType)
            continue;

         double lots = PositionGetDouble(POSITION_VOLUME);
         long units = Recovery_VolumeToUnitsFloor(lots, m_volumeStep);
         if(units <= 0 || lots <= 0.0) continue;

         SRecoveryCloseCandidate c;
         c.ticket       = ticket;
         c.openTime     = (datetime)PositionGetInteger(POSITION_TIME);
         c.units        = units;
         c.floatingCash = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
         int n = ArraySize(out);
         ArrayResize(out, n + 1);
         out[n] = c;

         activeUnits += units;
         activeLots += lots;
         weighted += PositionGetDouble(POSITION_PRICE_OPEN) * lots;
         signedCosts += PositionGetDouble(POSITION_SWAP);
         ulong identifier = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
         signedCosts += PositionEntryCosts(identifier);
      }

      if(activeUnits <= 0 || activeLots <= 0.0) return false;
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double avg = weighted / activeLots;
      bool hedgeIsBuy = wantedType == POSITION_TYPE_BUY;
      netBE = Recovery_NetBreakevenFromCosts(avg, activeLots, signedCosts,
                                              tickValue, m_tickSize, hedgeIsBuy);
      return netBE > 0.0;
   }

   long ActiveRecoveryHedgeUnits(const eRecoveryCoreDirection dir) const
   {
      SRecoveryCloseCandidate items[];
      long units = 0;
      double lots = 0.0, be = 0.0;
      if(!BuildRecoveryHedgeSnapshot(dir, items, units, lots, be)) return 0;
      return units;
   }

   void LogObservedStateChange(const eRecoveryCoreDirection dir,
                               const SRecoveryCycle &before,
                               const SRecoveryCycle &after)
   {
      if(before.state == after.state) return;
      Log_Info("Recovery", "SHADOW " + Recovery_DirectionName(dir) + " " +
               Recovery_StateName(before.state) + " -> " + Recovery_StateName(after.state));
   }

   bool BuildCurrentSplitPlan(const eRecoveryCoreDirection dir,
                              const long targetNewUnits,
                              SRecoveryBundleVolumeMeta &meta,
                              long &children[],
                              string &why) const
   {
      if(!Recovery_ReadBundleVolumeMeta(_Symbol, meta, why)) return false;
      int hedgeDir = Recovery_HedgeDirection(dir);
      long existingDirectionalUnits = Recovery_DirectionalExposureUnits(_Symbol,
                                                                         hedgeDir,
                                                                         meta.volumeStep);
      return Recovery_BuildBundlePlan(targetNewUnits,
                                      meta.minUnits,
                                      meta.maxOrderUnits,
                                      existingDirectionalUnits,
                                      meta.volumeLimitUnits,
                                      children,
                                      why);
   }

   bool BuildT6LockPlan(const eRecoveryCoreDirection dir,
                        SRecoveryLockTicket &tickets[],
                        SRecoveryLockSnapshot &snapshot,
                        double &targetSl,
                        string &why) const
   {
      targetSl = 0.0;
      if(!Recovery_BuildLockSnapshot(_Symbol, m_cfg.recoveryMagic, dir,
                                     m_volumeStep, m_tickSize,
                                     tickets, snapshot, why))
         return false;
      targetSl = Recovery_LockTargetPricePure(dir,
                                              snapshot.weightedEntry,
                                              snapshot.netBE,
                                              m_lockProfitDistancePrice,
                                              m_lockSafetyBufferPrice,
                                              m_tickSize,
                                              _Digits);
      if(targetSl <= 0.0)
      {
         why = "unable to derive strict net-positive lock target";
         return false;
      }
      return true;
   }

   void EvaluateDirection(const eRecoveryCoreDirection dir,
                          SRecoveryCorePositionSnapshot &positions[],
                          const double totalLots,
                          const EAContext &ctx)
   {
      SRecoveryCycle before;
      m_registry.GetCycle(dir, before);
      m_registry.ObserveCore(dir, ArraySize(positions), totalLots, 0.0, ctx.now);
      SRecoveryCycle cycle;
      m_registry.GetCycle(dir, cycle);
      EnsureT5Cycle(dir);
      LogObservedStateChange(dir, before, cycle);

      if(!cycle.armed && cycle.state == recovery_CORE_ONLY &&
         Recovery_DcaThresholdReached(cycle.coreCount, m_cfg.startAfterDca))
      {
         int thresholdIndex = m_cfg.startAfterDca;
         if(thresholdIndex >= 0 && thresholdIndex < ArraySize(positions))
         {
            ulong thresholdPosition = positions[thresholdIndex].ticket;
            SRecoveryEntryEvidence evidence;
            if(m_registry.FindCoreEntryEvidence(dir, thresholdPosition, evidence))
            {
               long anchorTicks = Recovery_PriceToTicksPure(evidence.price, m_tickSize);
               int dcaCount = Recovery_DcaCountFromCoreCount(cycle.coreCount);
               if(m_registry.LatchArmed(dir, evidence, dcaCount, anchorTicks, ctx.now))
               {
                  if(m_cfg.mode == recovery_ACTIVE) m_dirty = true;
                  Log_Info("Recovery", (m_cfg.mode == recovery_ACTIVE ? "ACTIVE " : "SHADOW ") +
                           Recovery_DirectionName(dir) +
                           " armed at DCA=" + (string)dcaCount +
                           " deal=" + (string)evidence.deal +
                           " position=" + (string)evidence.position +
                           " anchor=" + DoubleToString(evidence.price, _Digits));
               }
            }
            else if(!m_registry.AnchorEvidenceWaitLogged(dir))
            {
               Log_Warn("Recovery", "anchor" + (string)Recovery_CycleKey(dir),
                        "SHADOW threshold reached for " + Recovery_DirectionName(dir) +
                        " but confirmed threshold deal evidence is unavailable — waiting for reconciliation");
               m_registry.MarkAnchorEvidenceWaitLogged(dir);
            }
         }
      }

      m_registry.GetCycle(dir, cycle);
      if(m_cfg.mode == recovery_ACTIVE &&
         (before.state != cycle.state || before.coreCount != cycle.coreCount ||
          MathAbs(before.coreLots - cycle.coreLots) > m_volumeStep * 1e-7))
         m_dirty = true;

      // ACTIVE uses the real T9 scheduler below. The remaining block is the
      // T3 SHADOW decision path and must never latch a virtual decision in ACTIVE.
      if(m_cfg.mode != recovery_SHADOW) return;
      if(!cycle.armed || cycle.state != recovery_ARMED || cycle.shadowDecisionLatched)
         return;

      long bidTicks = Recovery_PriceToTicksPure(ctx.bid, m_tickSize);
      long askTicks = Recovery_PriceToTicksPure(ctx.ask, m_tickSize);
      if(!Recovery_AdverseGapHitTicks(dir, cycle.anchorTicks, bidTicks, askTicks, m_gapTicks))
         return;

      long targetUnits = Recovery_VolumeToUnitsFloor(cycle.coreLots, m_volumeStep);
      double triggerPrice = dir == recovery_CORE_BUY ? ctx.bid : ctx.ask;
      SRecoveryBundleVolumeMeta meta;
      long children[];
      string planWhy = "";
      if(!BuildCurrentSplitPlan(dir, targetUnits, meta, children, planWhy))
      {
         if(m_registry.MarkShadowHedgeBlocked(dir, targetUnits, triggerPrice, ctx.now))
            Log_Warn("Recovery", "bundle" + (string)Recovery_CycleKey(dir),
                     "SHADOW hedge bundle blocked for " + Recovery_DirectionName(dir) + ": " + planWhy);
         return;
      }

      if(m_registry.MarkShadowHedgeDecision(dir, targetUnits, triggerPrice,
                                             ArraySize(children), ctx.now))
      {
         string hedgeSide = Recovery_HedgeDirection(dir) == 0 ? "BUY" : "SELL";
         Log_Info("Recovery", "SHADOW would open " + hedgeSide + " logical hedge for " +
                  Recovery_DirectionName(dir) + " targetUnits=" + (string)targetUnits +
                  " children=" + (string)ArraySize(children) +
                  " trigger=" + DoubleToString(triggerPrice, _Digits));
      }
   }

   bool TransitionReconcile(const eRecoveryCoreDirection dir,
                            const datetime now,
                            const string reason)
   {
      SRecoveryCycle c;
      m_registry.GetCycle(dir, c);
      if(c.state == recovery_RECONCILE_REQUIRED) return true;
      bool ok = m_registry.Transition(dir, recovery_RECONCILE_REQUIRED, now, reason);
      if(ok && m_cfg.mode == recovery_ACTIVE) m_dirty = true;
      return ok;
   }

   long RawRecoveryUnits(const eRecoveryCoreDirection dir) const
   {
      long units = 0;
      long wantedType = Recovery_HedgeDirection(dir) == 0 ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol ||
            PositionGetInteger(POSITION_MAGIC) != m_cfg.recoveryMagic ||
            PositionGetInteger(POSITION_TYPE) != wantedType)
            continue;
         units += Recovery_VolumeToUnitsFloor(PositionGetDouble(POSITION_VOLUME), m_volumeStep);
      }
      return units;
   }

   long CoreUnits(const eRecoveryCoreDirection dir) const
   {
      return Recovery_CurrentCoreUnits(_Symbol, (long)Magic, dir, m_volumeStep);
   }

   int CoreCount(const eRecoveryCoreDirection dir) const
   {
      int count = 0;
      long wanted = dir == recovery_CORE_BUY ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == (long)Magic &&
            PositionGetInteger(POSITION_TYPE) == wanted)
            count++;
      }
      return count;
   }

   bool AnyRecoveryExposure() const
   {
      return RawRecoveryUnits(recovery_CORE_BUY) > 0 ||
             RawRecoveryUnits(recovery_CORE_SELL) > 0;
   }

   void ForceReconcile(const eRecoveryCoreDirection dir,
                       const datetime now,
                       const string reason)
   {
      SRecoveryCycle c;
      m_registry.GetCycle(dir, c);
      c.state = recovery_RECONCILE_REQUIRED;
      c.lastTransitionAt = now;
      c.transitionSequence++;
      m_registry.RestoreCycle(dir, c);
      m_activeReady = false;
      m_dirty = true;
      Log_Error("Recovery", "T9 reconcile required for " + Recovery_DirectionName(dir) + ": " + reason);
   }

   bool CursorAfter(const long dealTimeMsc, const ulong dealTicket,
                    const long cursorTimeMsc, const ulong cursorTicket) const
   {
      return dealTimeMsc > cursorTimeMsc ||
             (dealTimeMsc == cursorTimeMsc && dealTicket > cursorTicket);
   }

   void TrackSelectedDealCursor(const ulong deal)
   {
      if(deal == 0) return;
      long tmsc = HistoryDealGetInteger(deal, DEAL_TIME_MSC);
      if(CursorAfter(tmsc, deal, m_lastDealTimeMsc, m_lastDealTicket))
      {
         m_lastDealTimeMsc = tmsc;
         m_lastDealTicket = deal;
         m_dirty = true;
      }
   }

   void SeedLatestRelevantCursor()
   {
      m_lastDealTicket = 0;
      m_lastDealTimeMsc = 0;
      if(!HistorySelect(0, TimeCurrent())) return;
      int total = HistoryDealsTotal();
      for(int i = 0; i < total; i++)
      {
         ulong deal = HistoryDealGetTicket(i);
         if(deal == 0 || HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol) continue;
         long magic = HistoryDealGetInteger(deal, DEAL_MAGIC);
         if(magic != (long)Magic && magic != m_cfg.recoveryMagic) continue;
         TrackSelectedDealCursor(deal);
      }
   }

   bool BuildPersistPayload(SRecoveryPersistPayload &out) const
   {
      ZeroMemory(out);
      out.accountLogin = AccountInfoInteger(ACCOUNT_LOGIN);
      out.symbolHash = Recovery_StringHash(_Symbol);
      out.coreMagic = (long)Magic;
      out.recoveryMagic = m_cfg.recoveryMagic;
      out.volumeStep = m_volumeStep;
      out.tickSize = m_tickSize;
      out.startAfterDca = m_cfg.startAfterDca;
      out.savedAt = TimeCurrent();
      out.saveSequence = m_saveSequence + 1;
      out.lastDealTicket = m_lastDealTicket;
      out.lastDealTimeMsc = m_lastDealTimeMsc;
      m_registry.GetCycle(recovery_CORE_BUY, out.buyCycle);
      m_registry.GetCycle(recovery_CORE_SELL, out.sellCycle);
      out.buyT5 = m_t5[0];
      out.sellT5 = m_t5[1];
      out.buyT5CycleSerial = m_t5CycleSerial[0];
      out.sellT5CycleSerial = m_t5CycleSerial[1];
      out.buyHedgeRealizedBaseline = m_t5HedgeRealizedBaseline[0];
      out.sellHedgeRealizedBaseline = m_t5HedgeRealizedBaseline[1];
      out.buyAnchorWeighted = m_t6AnchorWeighted[0];
      out.sellAnchorWeighted = m_t6AnchorWeighted[1];
      out.buyAnchorUnits = m_t6AnchorUnits[0];
      out.sellAnchorUnits = m_t6AnchorUnits[1];
      out.buyRehedgeAnchorTicks = m_t6RehedgeAnchorTicks[0];
      out.sellRehedgeAnchorTicks = m_t6RehedgeAnchorTicks[1];
      out.buyLockTargetPrice = m_t6LockTargetPrice[0];
      out.sellLockTargetPrice = m_t6LockTargetPrice[1];
      out.buyPending = m_pending[0];
      out.sellPending = m_pending[1];
      return true;
   }

   bool ImportPersistPayload(const SRecoveryPersistPayload &p, string &why)
   {
      why = "";
      if(p.buyT5CycleSerial != p.buyCycle.cycleSerial ||
         p.sellT5CycleSerial != p.sellCycle.cycleSerial)
      {
         why = "T5 cycle serial does not match persisted Recovery cycle";
         return false;
      }
      if(!m_registry.RestoreCycle(recovery_CORE_BUY, p.buyCycle) ||
         !m_registry.RestoreCycle(recovery_CORE_SELL, p.sellCycle))
      {
         why = "persisted cycle failed registry restore validation";
         return false;
      }
      m_t5[0] = p.buyT5;
      m_t5[1] = p.sellT5;
      m_t5CycleSerial[0] = p.buyT5CycleSerial;
      m_t5CycleSerial[1] = p.sellT5CycleSerial;
      m_t5HedgeRealizedBaseline[0] = p.buyHedgeRealizedBaseline;
      m_t5HedgeRealizedBaseline[1] = p.sellHedgeRealizedBaseline;
      m_t6AnchorWeighted[0] = p.buyAnchorWeighted;
      m_t6AnchorWeighted[1] = p.sellAnchorWeighted;
      m_t6AnchorUnits[0] = p.buyAnchorUnits;
      m_t6AnchorUnits[1] = p.sellAnchorUnits;
      m_t6RehedgeAnchorTicks[0] = p.buyRehedgeAnchorTicks;
      m_t6RehedgeAnchorTicks[1] = p.sellRehedgeAnchorTicks;
      m_t6LockTargetPrice[0] = p.buyLockTargetPrice;
      m_t6LockTargetPrice[1] = p.sellLockTargetPrice;
      m_pending[0] = p.buyPending;
      m_pending[1] = p.sellPending;
      m_saveSequence = p.saveSequence;
      m_lastDealTicket = p.lastDealTicket;
      m_lastDealTimeMsc = p.lastDealTimeMsc;
      m_dirty = false;
      return true;
   }

   bool SaveState(string &why)
   {
      why = "";
      if(m_cfg.mode != recovery_ACTIVE) return true;
      if(m_persistenceBlocked)
      {
         why = "Recovery persistence is blocked by startup integrity/identity failure";
         return false;
      }
      SRecoveryPersistPayload payload;
      BuildPersistPayload(payload);
      if(!m_persistence.Save(payload, why))
      {
         m_activeReady = false;
         return false;
      }
      m_saveSequence = payload.saveSequence;
      m_dirty = false;
      return true;
   }

   bool FindCurrentThresholdEvidence(const eRecoveryCoreDirection dir,
                                     SRecoveryEntryEvidence &evidence,
                                     ulong &thresholdTicket,
                                     string &why)
   {
      why = "";
      thresholdTicket = 0;
      SRecoveryCorePositionSnapshot buyPos[];
      SRecoveryCorePositionSnapshot sellPos[];
      double buyLots = 0.0, sellLots = 0.0;
      BuildCoreSnapshots(buyPos, sellPos, buyLots, sellLots);
      int idx = m_cfg.startAfterDca;
      int n = dir == recovery_CORE_BUY ? ArraySize(buyPos) : ArraySize(sellPos);
      if(idx < 0 || idx >= n)
      {
         why = "current Core does not contain the configured threshold position";
         return false;
      }
      thresholdTicket = dir == recovery_CORE_BUY ? buyPos[idx].ticket : sellPos[idx].ticket;
      if(m_registry.FindCoreEntryEvidence(dir, thresholdTicket, evidence)) return true;
      if(!PositionSelectByTicket(thresholdTicket))
      {
         why = "threshold Core position is no longer selectable";
         return false;
      }
      ulong identifier = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
      if(identifier == 0 || !HistorySelectByPosition(identifier))
      {
         why = "threshold Core position history is unavailable";
         return false;
      }
      long wantedType = dir == recovery_CORE_BUY ? DEAL_TYPE_BUY : DEAL_TYPE_SELL;
      ulong bestDeal = 0;
      long bestTimeMsc = 0;
      int total = HistoryDealsTotal();
      for(int i = 0; i < total; i++)
      {
         ulong deal = HistoryDealGetTicket(i);
         if(deal == 0) continue;
         if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol ||
            HistoryDealGetInteger(deal, DEAL_MAGIC) != (long)Magic ||
            HistoryDealGetInteger(deal, DEAL_TYPE) != wantedType)
            continue;
         long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
         if(entry != DEAL_ENTRY_IN && entry != DEAL_ENTRY_INOUT) continue;
         long tmsc = HistoryDealGetInteger(deal, DEAL_TIME_MSC);
         if(bestDeal == 0 || tmsc < bestTimeMsc || (tmsc == bestTimeMsc && deal < bestDeal))
         {
            bestDeal = deal;
            bestTimeMsc = tmsc;
         }
      }
      if(bestDeal == 0 || !HistoryDealSelect(bestDeal))
      {
         why = "confirmed threshold Core entry deal is unavailable";
         return false;
      }
      evidence.valid = true;
      evidence.direction = dir;
      evidence.deal = bestDeal;
      evidence.position = thresholdTicket;
      evidence.price = HistoryDealGetDouble(bestDeal, DEAL_PRICE);
      evidence.time = (datetime)HistoryDealGetInteger(bestDeal, DEAL_TIME);
      if(evidence.price <= 0.0)
      {
         why = "threshold Core deal price is invalid";
         return false;
      }
      m_registry.RecordCoreEntryEvidence(dir, evidence.deal, evidence.position,
                                         evidence.price, evidence.time);
      return true;
   }

   bool EnsureCurrentAnchor(const eRecoveryCoreDirection dir,
                            const datetime now,
                            string &why)
   {
      SRecoveryCycle c;
      m_registry.GetCycle(dir, c);
      if(c.armed && c.anchorDeal != 0 && c.anchorPrice > 0.0 && c.anchorTicks > 0)
         return true;
      if(!Recovery_DcaThresholdReached(CoreCount(dir), m_cfg.startAfterDca)) return true;
      SRecoveryEntryEvidence evidence;
      ulong thresholdTicket = 0;
      if(!FindCurrentThresholdEvidence(dir, evidence, thresholdTicket, why)) return false;
      long ticks = Recovery_PriceToTicksPure(evidence.price, m_tickSize);
      if(ticks <= 0) { why = "threshold anchor is not representable in symbol ticks"; return false; }
      if(!c.armed)
      {
         int dcaCount = Recovery_DcaCountFromCoreCount(CoreCount(dir));
         if(!m_registry.LatchArmed(dir, evidence, dcaCount, ticks, now))
         {
            why = "registry rejected reconstructed threshold anchor";
            return false;
         }
      }
      else
      {
         c.anchorDeal = evidence.deal;
         c.anchorPosition = thresholdTicket;
         c.anchorPrice = evidence.price;
         c.anchorTicks = ticks;
         c.anchorTime = evidence.time;
         if(!m_registry.RestoreCycle(dir, c))
         {
            why = "registry rejected reconstructed persisted anchor";
            return false;
         }
      }
      m_dirty = true;
      return true;
   }

   void ApplyPersistReplayDeal(const ulong deal)
   {
      if(deal == 0 || !HistoryDealSelect(deal)) return;
      long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY) return;
      if(DealSeen(deal)) return;
      long magic = HistoryDealGetInteger(deal, DEAL_MAGIC);
      long type = HistoryDealGetInteger(deal, DEAL_TYPE);
      double cash = Recovery_DealCashPure(HistoryDealGetDouble(deal, DEAL_PROFIT),
                                          HistoryDealGetDouble(deal, DEAL_SWAP),
                                          HistoryDealGetDouble(deal, DEAL_COMMISSION),
                                          HistoryDealGetDouble(deal, DEAL_FEE));
      if(magic == m_cfg.recoveryMagic)
      {
         eRecoveryCoreDirection dir = recovery_CORE_BUY;
         if(type == DEAL_TYPE_BUY) dir = recovery_CORE_BUY;
         else if(type == DEAL_TYPE_SELL) dir = recovery_CORE_SELL;
         else return;
         SRecoveryCycle cycle;
         m_registry.GetCycle(dir, cycle);
         if(cycle.state != recovery_HEDGE_TP_PENDING) return;
         EnsureT5Cycle(dir);
         int idx = DirIndex(dir);
         long units = Recovery_VolumeToUnitsFloor(HistoryDealGetDouble(deal, DEAL_VOLUME), m_volumeStep);
         double price = HistoryDealGetDouble(deal, DEAL_PRICE);
         if(units > 0 && price > 0.0)
         {
            m_t6AnchorWeighted[idx] += price * (double)units;
            m_t6AnchorUnits[idx] += units;
         }
         Recovery_LedgerApplyHedgeDeal(m_t5[idx].ledger, cash, units);
         MarkDealSeen(deal);
         m_dirty = true;
         return;
      }
      if(magic == (long)Magic)
      {
         eRecoveryCoreDirection dir = recovery_CORE_BUY;
         if(type == DEAL_TYPE_SELL) dir = recovery_CORE_BUY;
         else if(type == DEAL_TYPE_BUY) dir = recovery_CORE_SELL;
         else return;
         SRecoveryCycle cycle;
         m_registry.GetCycle(dir, cycle);
         if(cycle.state != recovery_CORE_CLOSE_PENDING) return;
         EnsureT5Cycle(dir);
         Recovery_LedgerApplyCoreDeal(m_t5[DirIndex(dir)].ledger, cash);
         MarkDealSeen(deal);
         m_dirty = true;
      }
   }

   bool ReplayDealsAfterCursor(string &why)
   {
      why = "";
      long cursorTime = m_lastDealTimeMsc;
      ulong cursorTicket = m_lastDealTicket;
      if(!HistorySelect(0, TimeCurrent()))
      {
         why = "account deal history is unavailable for Recovery replay";
         return false;
      }
      ulong replay[];
      ArrayResize(replay, 0);
      int total = HistoryDealsTotal();
      for(int i = 0; i < total; i++)
      {
         ulong deal = HistoryDealGetTicket(i);
         if(deal == 0 || HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol) continue;
         long magic = HistoryDealGetInteger(deal, DEAL_MAGIC);
         if(magic != (long)Magic && magic != m_cfg.recoveryMagic) continue;
         long tmsc = HistoryDealGetInteger(deal, DEAL_TIME_MSC);
         if(!CursorAfter(tmsc, deal, cursorTime, cursorTicket)) continue;
         int n = ArraySize(replay);
         ArrayResize(replay, n + 1);
         replay[n] = deal;
      }
      for(int i = 0; i < ArraySize(replay); i++)
      {
         ulong deal = replay[i];
         ApplyPersistReplayDeal(deal);
         if(HistoryDealSelect(deal)) TrackSelectedDealCursor(deal);
      }
      return true;
   }

   void UpdateBrokerMetrics(const eRecoveryCoreDirection dir)
   {
      SRecoveryCycle c;
      m_registry.GetCycle(dir, c);
      int coreCount = CoreCount(dir);
      long coreUnits = CoreUnits(dir);
      long hedgeUnits = RawRecoveryUnits(dir);
      c.coreCount = coreCount;
      c.coreLots = Recovery_UnitsToVolume(coreUnits, m_volumeStep);
      c.activeHedgeLots = Recovery_UnitsToVolume(hedgeUnits, m_volumeStep);
      SRecoveryCloseCandidate hedge[];
      long snapUnits = 0;
      double snapLots = 0.0, snapBE = 0.0;
      if(BuildRecoveryHedgeSnapshot(dir, hedge, snapUnits, snapLots, snapBE))
      {
         c.activeHedgeLots = snapLots;
         c.hedgeNetBE = snapBE;
      }
      else if(hedgeUnits == 0)
         c.hedgeNetBE = 0.0;
      c.coveragePercent = Recovery_CoveragePercent(c.coreLots, c.activeHedgeLots);
      c.corridorPrice = Recovery_CorridorPrice(dir, c.coreNetBE, c.hedgeNetBE);
      m_registry.RestoreCycle(dir, c);
   }

   bool PendingEffectConfirmed(const eRecoveryCoreDirection dir,
                               const SRecoveryPersistPending &p) const
   {
      if(!p.active) return true;
      if(p.commandType == EXEC_CMD_RECOVERY_OPEN)
         return Recovery_PendingVolumeEffectConfirmed(true, p.observedUnitsBefore,
                                                      p.targetUnits, RawRecoveryUnits(dir));
      if(p.commandType == EXEC_CMD_RECOVERY_CLOSE)
      {
         long current = p.ownerMagic == m_cfg.recoveryMagic ? RawRecoveryUnits(dir) : CoreUnits(dir);
         return Recovery_PendingVolumeEffectConfirmed(false, p.observedUnitsBefore,
                                                      p.targetUnits, current);
      }
      if(p.commandType == EXEC_CMD_RECOVERY_MODIFY)
      {
         if(p.ticket == 0 || !PositionSelectByTicket(p.ticket)) return false;
         if(PositionGetInteger(POSITION_MAGIC) != m_cfg.recoveryMagic) return false;
         return Recovery_LockSatisfiedPure(dir, PositionGetDouble(POSITION_SL),
                                           p.targetPrice, m_tickSize);
      }
      return false;
   }

   bool ResolvePendingInternal(CExecutionLayer &exec,
                               const eRecoveryCoreDirection dir,
                               const datetime now,
                               string &why)
   {
      why = "";
      int idx = DirIndex(dir);
      if(!m_pending[idx].active) return true;
      int cycleKey = Recovery_CycleKey(dir);
      exec.ReconcileCycle(cycleKey);
      if(exec.HasReconcileRequired(cycleKey))
      {
         why = "execution journal requires strict reconciliation";
         ForceReconcile(dir, now, why);
         return false;
      }
      if(exec.HasPendingForCycle(cycleKey)) return true;
      if(!PendingEffectConfirmed(dir, m_pending[idx]))
      {
         why = "durable command has no broker-observable exact effect after journal disappeared/restart";
         ForceReconcile(dir, now, why);
         return false;
      }
      SRecoveryCycle c;
      m_registry.GetCycle(dir, c);
      if(m_pending[idx].commandType == EXEC_CMD_RECOVERY_OPEN && c.state == recovery_HEDGE_BUILDING)
      {
         c.bundleChildInFlight = false;
         m_registry.RestoreCycle(dir, c);
      }
      Recovery_PendingInit(m_pending[idx]);
      m_dirty = true;
      return true;
   }

   bool ReconcileDirection(CExecutionLayer &exec,
                           const eRecoveryCoreDirection dir,
                           const datetime now,
                           string &why)
   {
      why = "";
      int idx = DirIndex(dir);
      SRecoveryPersistPending beforePending = m_pending[idx];
      if(!ResolvePendingInternal(exec, dir, now, why)) return false;

      SRecoveryCycle c;
      m_registry.GetCycle(dir, c);
      long currentCore = CoreUnits(dir);
      long currentHedge = RawRecoveryUnits(dir);
      long persistedCore = Recovery_VolumeToUnitsFloor(c.coreLots, m_volumeStep);
      bool allowedCoreDelta = beforePending.active &&
                              beforePending.commandType == EXEC_CMD_RECOVERY_CLOSE &&
                              beforePending.ownerMagic == (long)Magic;
      if(c.state != recovery_CORE_ONLY && c.state != recovery_COMPLETED &&
         persistedCore > 0 && currentCore != persistedCore && !allowedCoreDelta)
      {
         why = "Core exposure differs from persisted broker snapshot without a durable Core-close command";
         ForceReconcile(dir, now, why);
         return false;
      }

      switch(c.state)
      {
         case recovery_CORE_ONLY:
            if(currentHedge > 0)
            {
               why = "Recovery hedge exists while persisted cycle is CORE_ONLY";
               ForceReconcile(dir, now, why);
               return false;
            }
            if(Recovery_DcaThresholdReached(CoreCount(dir), m_cfg.startAfterDca) &&
               !EnsureCurrentAnchor(dir, now, why))
            {
               ForceReconcile(dir, now, why);
               return false;
            }
            break;

         case recovery_ARMED:
            if(currentCore <= 0 || currentHedge != 0 || !EnsureCurrentAnchor(dir, now, why))
            {
               if(why == "") why = "ARMED restart requires Core exposure, zero Recovery hedge and a confirmed anchor";
               ForceReconcile(dir, now, why);
               return false;
            }
            break;

         case recovery_HEDGE_BUILDING:
         {
            if(currentCore <= 0 || c.bundleTargetUnits <= 0 || c.bundleBaselineActiveUnits < 0)
            {
               why = "invalid HEDGE_BUILDING persisted target/baseline/Core exposure";
               ForceReconcile(dir, now, why);
               return false;
            }
            long confirmed = currentHedge - c.bundleBaselineActiveUnits;
            if(confirmed < 0 || confirmed > c.bundleTargetUnits)
            {
               why = "HEDGE_BUILDING broker coverage is outside persisted exact bundle bounds";
               ForceReconcile(dir, now, why);
               return false;
            }
            if(c.bundleChildInFlight && !beforePending.active)
            {
               why = "HEDGE_BUILDING child-in-flight flag has no durable command metadata";
               ForceReconcile(dir, now, why);
               return false;
            }
            c.bundleChildInFlight = false;
            c.bundleConfirmedUnits = confirmed;
            c.bundlePartialCoverage = confirmed > 0 && confirmed < c.bundleTargetUnits;
            c.bundleCoveragePercent = Recovery_BundleCoveragePercent(confirmed, c.bundleTargetUnits);
            if(confirmed == c.bundleTargetUnits)
            {
               c.bundleComplete = true;
               c.bundlePartialCoverage = false;
               c.bundleCoveragePercent = 100.0;
               c.state = recovery_HEDGE_ACTIVE;
            }
            m_registry.RestoreCycle(dir, c);
            break;
         }

         case recovery_HEDGE_ACTIVE:
            if(currentCore <= 0 || currentHedge <= 0)
            {
               why = "HEDGE_ACTIVE restart requires observable Core and Recovery hedge exposure";
               ForceReconcile(dir, now, why);
               return false;
            }
            break;

         case recovery_HEDGE_TP_PENDING:
            if(currentCore <= 0 || m_t5[idx].hedgeCloseBaselineUnits <= 0 ||
               m_t5[idx].hedgeCloseTargetUnits <= 0)
            {
               why = "HEDGE_TP_PENDING runtime snapshot is incomplete";
               ForceReconcile(dir, now, why);
               return false;
            }
            if(!RefreshHedgePartialClose(exec, dir, now, why) &&
               m_registry.GetCycle(dir, c), c.state == recovery_RECONCILE_REQUIRED)
               return false;
            break;

         case recovery_CORE_CLOSE_PENDING:
            if(currentHedge <= 0)
            {
               why = "CORE_CLOSE_PENDING restart has no remaining Recovery hedge";
               ForceReconcile(dir, now, why);
               return false;
            }
            RefreshCoreClose(exec, dir, now, why);
            m_registry.GetCycle(dir, c);
            if(c.state == recovery_RECONCILE_REQUIRED) return false;
            break;

         case recovery_HEDGE_LOCK_PENDING:
            if(currentHedge <= 0 || m_t6RehedgeAnchorTicks[idx] <= 0)
            {
               why = "HEDGE_LOCK_PENDING restart lacks hedge exposure or confirmed close anchor";
               ForceReconcile(dir, now, why);
               return false;
            }
            RefreshHedgeLock(exec, dir, now, why);
            m_registry.GetCycle(dir, c);
            if(c.state == recovery_RECONCILE_REQUIRED) return false;
            break;

         case recovery_HEDGE_LOCKED:
         case recovery_REHEDGE_PENDING:
            if(currentCore <= 0 || currentHedge <= 0 || m_t6RehedgeAnchorTicks[idx] <= 0)
            {
               why = "locked/rehedge restart lacks Core, hedge, or confirmed re-hedge anchor";
               ForceReconcile(dir, now, why);
               return false;
            }
            break;

         case recovery_COMPLETED:
            if(currentCore != 0 || currentHedge != 0)
            {
               why = "COMPLETED persisted cycle conflicts with broker exposure";
               ForceReconcile(dir, now, why);
               return false;
            }
            break;

         case recovery_PAUSE_SOFT:
            why = "PAUSE_SOFT resume target is not durable enough for automatic restart";
            ForceReconcile(dir, now, why);
            return false;

         case recovery_PAUSE_HARD:
         case recovery_RECONCILE_REQUIRED:
         case recovery_GLOBAL_STOP:
            why = "persisted Recovery state is intentionally fail-closed";
            m_activeReady = false;
            return false;
      }
      UpdateBrokerMetrics(dir);
      m_dirty = true;
      return true;
   }

   bool FreshBootstrap(const datetime now, string &why)
   {
      why = "";
      if(AnyRecoveryExposure())
      {
         why = "Recovery persistence is missing while RecoveryMagic exposure exists";
         m_persistenceBlocked = true;
         m_activeReady = false;
         return false;
      }
      SRecoveryCorePositionSnapshot buyPos[];
      SRecoveryCorePositionSnapshot sellPos[];
      double buyLots = 0.0, sellLots = 0.0;
      BuildCoreSnapshots(buyPos, sellPos, buyLots, sellLots);
      m_registry.ObserveCore(recovery_CORE_BUY, ArraySize(buyPos), buyLots, 0.0, now);
      m_registry.ObserveCore(recovery_CORE_SELL, ArraySize(sellPos), sellLots, 0.0, now);
      if(Recovery_DcaThresholdReached(ArraySize(buyPos), m_cfg.startAfterDca) &&
         !EnsureCurrentAnchor(recovery_CORE_BUY, now, why)) return false;
      if(Recovery_DcaThresholdReached(ArraySize(sellPos), m_cfg.startAfterDca) &&
         !EnsureCurrentAnchor(recovery_CORE_SELL, now, why)) return false;
      UpdateBrokerMetrics(recovery_CORE_BUY);
      UpdateBrokerMetrics(recovery_CORE_SELL);
      SeedLatestRelevantCursor();
      m_dirty = true;
      return true;
   }

   bool DriveActiveDirection(CExecutionLayer &exec,
                             const eRecoveryCoreDirection dir,
                             const EAContext &ctx,
                             string &why)
   {
      why = "";
      SRecoveryCycle c;
      m_registry.GetCycle(dir, c);
      int cycleKey = Recovery_CycleKey(dir);

      if(m_pending[DirIndex(dir)].active)
      {
         if(!ResolvePendingInternal(exec, dir, ctx.now, why)) return false;
         if(exec.HasPendingForCycle(cycleKey)) return true;
         m_registry.GetCycle(dir, c);
      }

      if(c.state == recovery_ARMED)
      {
         long bidTicks = Recovery_PriceToTicksPure(ctx.bid, m_tickSize);
         long askTicks = Recovery_PriceToTicksPure(ctx.ask, m_tickSize);
         if(!Recovery_AdverseGapHitTicks(dir, c.anchorTicks, bidTicks, askTicks, m_gapTicks)) return false;
         if(PrepareInitialBundle(dir, ctx.now, why)) { m_dirty = true; return true; }
         return false;
      }

      if(c.state == recovery_HEDGE_BUILDING)
      {
         RefreshBundleFromBroker(exec, dir, ctx.now);
         m_registry.GetCycle(dir, c);
         m_dirty = true;
         if(c.state != recovery_HEDGE_BUILDING) return true;
         if(exec.HasPendingForCycle(cycleKey) || m_pending[DirIndex(dir)].active) return true;
         if(SubmitNextBundleChild(exec, dir, why)) return true;
         return false;
      }

      if(c.state == recovery_HEDGE_ACTIVE)
      {
         if(PrepareVirtualHedgeTp(dir, ctx, why)) { m_dirty = true; return true; }
         why = "";
         return false;
      }

      if(c.state == recovery_HEDGE_TP_PENDING)
      {
         RefreshHedgePartialClose(exec, dir, ctx.now, why);
         m_registry.GetCycle(dir, c);
         m_dirty = true;
         if(c.state != recovery_HEDGE_TP_PENDING) return true;
         if(exec.HasPendingForCycle(cycleKey) || m_pending[DirIndex(dir)].active) return true;
         if(SubmitNextHedgePartialClose(exec, dir, why)) return true;
         return false;
      }

      if(c.state == recovery_CORE_CLOSE_PENDING)
      {
         RefreshCoreClose(exec, dir, ctx.now, why);
         m_registry.GetCycle(dir, c);
         m_dirty = true;
         if(c.state != recovery_CORE_CLOSE_PENDING) return true;
         if(exec.HasPendingForCycle(cycleKey) || m_pending[DirIndex(dir)].active) return true;
         if(SubmitNextCoreClose(exec, dir, why)) return true;
         return false;
      }

      if(c.state == recovery_HEDGE_LOCK_PENDING)
      {
         RefreshHedgeLock(exec, dir, ctx.now, why);
         m_registry.GetCycle(dir, c);
         m_dirty = true;
         if(c.state != recovery_HEDGE_LOCK_PENDING) return true;
         if(exec.HasPendingForCycle(cycleKey) || m_pending[DirIndex(dir)].active) return true;
         if(SubmitNextHedgeLock(exec, dir, ctx, why)) return true;
         return false;
      }

      if(c.state == recovery_HEDGE_LOCKED)
      {
         if(EvaluateRehedge(dir, ctx, why)) { m_dirty = true; return true; }
         why = "";
         return false;
      }

      if(c.state == recovery_REHEDGE_PENDING)
      {
         if(PrepareRehedgeBundle(dir, ctx.now, why)) { m_dirty = true; return true; }
         return false;
      }
      return false;
   }


public:
   CRecoveryEngine(void)
   {
      m_initialized = false;
      m_tickSize = 0.0;
      m_volumeStep = 0.0;
      m_isGold = false;
      m_gapTicks = 0;
      m_tpDistancePrice = 0.0;
      m_lockProfitDistancePrice = 0.0;
      m_lockSafetyBufferPrice = 0.0;
      m_rehedgeGapTicks = 0;
      m_activeReady = false;
      m_persistLoaded = false;
      m_persistMissing = false;
      m_persistenceBlocked = false;
      m_dirty = false;
      m_saveSequence = 0;
      m_lastDealTicket = 0;
      m_lastDealTimeMsc = 0;
      m_startupFaultReason = "";
      Recovery_PendingInit(m_pending[0]);
      Recovery_PendingInit(m_pending[1]);
      m_seenWrite = 0;
      m_seenStored = 0;
      m_t5CycleSerial[0] = 0;
      m_t5CycleSerial[1] = 0;
      Recovery_T5RuntimeInit(m_t5[0]);
      Recovery_T5RuntimeInit(m_t5[1]);
      ResetT6Cycle(0);
      ResetT6Cycle(1);
      for(int i = 0; i < BD_RECOVERY_T5_SEEN_DEALS; i++) m_seenDeals[i] = 0;
   }

   bool Init()
   {
      Recovery_LoadFoundationConfig(m_cfg);
      m_registry.Init();
      Recovery_T5RuntimeInit(m_t5[0]);
      Recovery_T5RuntimeInit(m_t5[1]);
      ResetT6Cycle(0);
      ResetT6Cycle(1);
      m_t5CycleSerial[0] = 1;
      m_t5CycleSerial[1] = 1;
      m_seenWrite = 0;
      m_seenStored = 0;
      for(int i = 0; i < BD_RECOVERY_T5_SEEN_DEALS; i++) m_seenDeals[i] = 0;
      Recovery_PendingInit(m_pending[0]);
      Recovery_PendingInit(m_pending[1]);
      m_activeReady = false;
      m_persistLoaded = false;
      m_persistMissing = false;
      m_persistenceBlocked = false;
      m_dirty = false;
      m_saveSequence = 0;
      m_lastDealTicket = 0;
      m_lastDealTimeMsc = 0;
      m_startupFaultReason = "";
      m_initialized = false;

      if(m_cfg.mode == recovery_OFF)
      {
         m_initialized = true;
         return true;
      }

      string t5Why = "";
      if(!Recovery_ValidateT5Config(m_cfg.mode, m_cfg.hedgeTpPips,
                                    m_cfg.hedgePartialClosePercent,
                                    m_cfg.coreCloseMode, t5Why))
      {
         Log_Error("Recovery", "invalid T5 config: " + t5Why);
         return false;
      }

      string t6Why = "";
      if(!Recovery_ValidateT6Config(m_cfg.mode,
                                    m_cfg.hedgeLockNetProfitPips,
                                    m_cfg.hedgeLockSafetyBufferPips,
                                    m_cfg.reHedgeGapPips,
                                    m_cfg.maxHedgeGenerations,
                                    t6Why))
      {
         Log_Error("Recovery", "invalid T6 config: " + t6Why);
         return false;
      }

      m_tickSize   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      m_volumeStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      m_isGold     = Sym_IsGold();
      if(m_tickSize <= 0.0 || m_volumeStep <= 0.0)
      {
         Log_Error("Recovery", "invalid symbol tick-size/volume-step metadata for SHADOW");
         return false;
      }

      SRecoveryBundleVolumeMeta meta;
      string volumeWhy = "";
      if(!Recovery_ReadBundleVolumeMeta(_Symbol, meta, volumeWhy))
      {
         Log_Error("Recovery", "invalid Recovery bundle volume metadata: " + volumeWhy);
         return false;
      }

      m_gapTicks = Recovery_PipsToTicksPure(m_cfg.hedgeGapPips, m_isGold,
                                            _Point, _Digits, m_tickSize);
      m_tpDistancePrice = Recovery_PipsToPricePure(m_cfg.hedgeTpPips, m_isGold,
                                                   _Point, _Digits);
      m_lockProfitDistancePrice = Recovery_PipsToPricePure(m_cfg.hedgeLockNetProfitPips,
                                                           m_isGold, _Point, _Digits);
      m_lockSafetyBufferPrice = Recovery_PipsToPricePure(m_cfg.hedgeLockSafetyBufferPips,
                                                         m_isGold, _Point, _Digits);
      m_rehedgeGapTicks = Recovery_PipsToTicksPure(m_cfg.reHedgeGapPips, m_isGold,
                                                   _Point, _Digits, m_tickSize);
      if(m_cfg.hedgeGapPips > 0.0 && m_gapTicks <= 0)
      {
         Log_Error("Recovery", "HedgeGapPips_ is not representable in symbol ticks");
         return false;
      }
      if(m_cfg.hedgeTpPips > 0.0 && m_tpDistancePrice <= 0.0)
      {
         Log_Error("Recovery", "HedgeTPPips_ is not representable in price units");
         return false;
      }
      if(m_cfg.hedgeLockNetProfitPips > 0.0 && m_lockProfitDistancePrice <= 0.0)
      {
         Log_Error("Recovery", "HedgeLockNetProfitPips_ is not representable in price units");
         return false;
      }
      if(m_lockSafetyBufferPrice <= 0.0)
      {
         Log_Error("Recovery", "HedgeLockSafetyBufferPips_ is not representable in price units");
         return false;
      }
      if(m_cfg.reHedgeGapPips > 0.0 && m_rehedgeGapTicks <= 0)
      {
         Log_Error("Recovery", "ReHedgeGapPips_ is not representable in symbol ticks");
         return false;
      }

      if(m_cfg.mode == recovery_ACTIVE)
      {
         m_persistence.Init(_Symbol, AccountInfoInteger(ACCOUNT_LOGIN),
                            (long)Magic, m_cfg.recoveryMagic);
         SRecoveryPersistPayload payload;
         string loadWhy = "";
         eRecoveryPersistLoadStatus st = m_persistence.Load(payload, loadWhy);
         if(st == recovery_PERSIST_NOT_FOUND)
            m_persistMissing = true;
         else if(st == recovery_PERSIST_OK)
         {
            if(!Recovery_PersistPayloadIdentityValid(payload,
                  AccountInfoInteger(ACCOUNT_LOGIN), Recovery_StringHash(_Symbol),
                  (long)Magic, m_cfg.recoveryMagic, m_volumeStep, m_tickSize,
                  m_cfg.startAfterDca) || !ImportPersistPayload(payload, loadWhy))
            {
               m_persistenceBlocked = true;
               m_startupFaultReason = loadWhy == "" ? "Recovery state identity/config mismatch" : loadWhy;
            }
            else
               m_persistLoaded = true;
         }
         else
         {
            m_persistenceBlocked = true;
            m_startupFaultReason = loadWhy == "" ? "Recovery state integrity/I/O failure" : loadWhy;
         }
      }

      m_initialized = true;
      if(m_cfg.mode == recovery_SHADOW)
         Log_Info("Recovery", "SHADOW registry/FSM + smart-split + T5/T6 mechanics enabled; no Recovery trade requests will be sent");
      else
         Log_Info("Recovery", "ACTIVE mechanics initialized; trading remains blocked until T9 startup reconciliation succeeds");
      return true;
   }

   void OnTick(const EAContext &ctx)
   {
      if(!m_initialized || m_cfg.mode == recovery_OFF) return;
      if(m_cfg.mode == recovery_ACTIVE && !m_activeReady) return;

      SRecoveryCorePositionSnapshot buyPos[];
      SRecoveryCorePositionSnapshot sellPos[];
      double buyLots = 0.0, sellLots = 0.0;
      BuildCoreSnapshots(buyPos, sellPos, buyLots, sellLots);

      EvaluateDirection(recovery_CORE_BUY, buyPos, buyLots, ctx);
      EvaluateDirection(recovery_CORE_SELL, sellPos, sellLots, ctx);
   }

   void OnTradeTransaction(const MqlTradeTransaction &trans)
   {
      if(!m_initialized || m_cfg.mode == recovery_OFF) return;
      if(trans.type != TRADE_TRANSACTION_DEAL_ADD || trans.deal == 0 || trans.symbol != _Symbol)
         return;
      if(!HistoryDealSelect(trans.deal)) return;
      if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol) return;

      long magic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
      long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
      long type  = HistoryDealGetInteger(trans.deal, DEAL_TYPE);
      if(m_cfg.mode == recovery_ACTIVE &&
         (magic == (long)Magic || magic == m_cfg.recoveryMagic))
         TrackSelectedDealCursor(trans.deal);

      if(magic == (long)Magic && (entry == DEAL_ENTRY_IN || entry == DEAL_ENTRY_INOUT))
      {
         eRecoveryCoreDirection dir = recovery_CORE_BUY;
         if(type == DEAL_TYPE_BUY) dir = recovery_CORE_BUY;
         else if(type == DEAL_TYPE_SELL) dir = recovery_CORE_SELL;
         else return;
         ulong position = trans.position;
         if(position == 0) position = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
         double price = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
         datetime dealTime = (datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME);
         m_registry.RecordCoreEntryEvidence(dir, trans.deal, position, price, dealTime);
         if(m_cfg.mode == recovery_ACTIVE)
         {
            SRecoveryCorePositionSnapshot buyPos[];
            SRecoveryCorePositionSnapshot sellPos[];
            double buyLots = 0.0, sellLots = 0.0;
            BuildCoreSnapshots(buyPos, sellPos, buyLots, sellLots);
            m_registry.ObserveCore(recovery_CORE_BUY, ArraySize(buyPos), buyLots, 0.0, dealTime);
            m_registry.ObserveCore(recovery_CORE_SELL, ArraySize(sellPos), sellLots, 0.0, dealTime);
            m_dirty = true;
            string persistWhy = "";
            if(!SaveState(persistWhy))
               Log_Error("Recovery", "cannot persist confirmed Core entry evidence: " + persistWhy);
         }
         return;
      }

      if(m_cfg.mode != recovery_ACTIVE) return;
      ApplyPersistReplayDeal(trans.deal);
      string persistWhy = "";
      if(m_dirty && !SaveState(persistWhy))
         Log_Error("Recovery", "cannot persist confirmed deal evidence: " + persistWhy);
   }

   //--- T4 execution bridge -------------------------------------------------
   bool PrepareInitialBundle(const eRecoveryCoreDirection dir,
                             const datetime now,
                             string &why)
   {
      why = "";
      if(m_cfg.mode != recovery_ACTIVE)
      {
         why = "bundle execution bridge requires RecoveryMode=ACTIVE";
         return false;
      }
      SRecoveryCycle cycle;
      m_registry.GetCycle(dir, cycle);
      if(cycle.state != recovery_ARMED || !cycle.armed)
      {
         why = "cycle is not ARMED";
         return false;
      }
      if(!Recovery_GenerationCanStartPure(cycle.hedgeGeneration, m_cfg.maxHedgeGenerations))
      {
         why = "starting the next logical hedge generation would exceed MaxHedgeGenerations_";
         return false;
      }
      long coreUnits = Recovery_VolumeToUnitsFloor(cycle.coreLots, m_volumeStep);
      long activeUnits = ActiveRecoveryHedgeUnits(dir);
      if(coreUnits <= 0)
      {
         why = "Core exposure is not representable in volume units";
         return false;
      }
      if(activeUnits != 0)
      {
         why = "initial bundle requires zero pre-existing Recovery hedge units";
         return false;
      }

      SRecoveryBundleVolumeMeta meta;
      long children[];
      if(!BuildCurrentSplitPlan(dir, coreUnits, meta, children, why)) return false;
      return m_registry.BeginBundle(dir, coreUnits, activeUnits, now);
   }

   bool RefreshBundleFromBroker(CExecutionLayer &exec,
                                const eRecoveryCoreDirection dir,
                                const datetime now)
   {
      if(m_cfg.mode != recovery_ACTIVE) return false;
      SRecoveryCycle cycle;
      m_registry.GetCycle(dir, cycle);
      if(cycle.state != recovery_HEDGE_BUILDING) return false;
      int cycleKey = Recovery_CycleKey(dir);
      exec.ReconcileCycle(cycleKey);
      return m_registry.ObserveBundle(dir,
                                      ActiveRecoveryHedgeUnits(dir),
                                      exec.HasPendingForCycle(cycleKey),
                                      exec.HasReconcileRequired(cycleKey),
                                      now);
   }

   bool SubmitNextBundleChild(CExecutionLayer &exec,
                              const eRecoveryCoreDirection dir,
                              string &why)
   {
      why = "";
      if(m_cfg.mode != recovery_ACTIVE)
      {
         why = "bundle execution bridge requires RecoveryMode=ACTIVE";
         return false;
      }
      SRecoveryCycle cycle;
      m_registry.GetCycle(dir, cycle);
      if(cycle.state != recovery_HEDGE_BUILDING)
      {
         why = "cycle is not HEDGE_BUILDING";
         return false;
      }

      int cycleKey = Recovery_CycleKey(dir);
      if(exec.HasReconcileRequired(cycleKey))
      {
         why = "execution layer requires reconciliation";
         return false;
      }
      if(exec.HasPendingForCycle(cycleKey) || !m_registry.BundleCanSubmitNext(dir))
      {
         why = "one child is already in flight or bundle is blocked/complete";
         return false;
      }

      SRecoveryBundleVolumeMeta meta;
      if(!Recovery_ReadBundleVolumeMeta(_Symbol, meta, why)) return false;
      long childUnits = m_registry.BundleNextChildUnits(dir, meta.minUnits, meta.maxOrderUnits);
      if(childUnits <= 0)
      {
         why = "remaining exact bundle target cannot form a legal child; reconciliation required";
         m_registry.ObserveBundle(dir, ActiveRecoveryHedgeUnits(dir), false, true, TimeCurrent());
         return false;
      }

      int hedgeDir = Recovery_HedgeDirection(dir);
      long existingDirectionalUnits = Recovery_DirectionalExposureUnits(_Symbol, hedgeDir, meta.volumeStep);
      if(!Recovery_VolumeLimitAllows(childUnits, existingDirectionalUnits, meta.volumeLimitUnits))
      {
         why = "next child would exceed current SYMBOL_VOLUME_LIMIT";
         m_registry.MarkBundleChildRejected(dir);
         return false;
      }
      if(!Recovery_ChildMarginPreflight(_Symbol, hedgeDir, childUnits, meta.volumeStep, why))
      {
         m_registry.MarkBundleChildRejected(dir);
         return false;
      }

      double volume = Recovery_UnitsToVolume(childUnits, meta.volumeStep);
      double normalized = Grid_NormalizeVolume(volume);
      if(MathAbs(normalized - volume) > meta.volumeStep * 1e-7)
      {
         why = "legacy execution normalization would alter exact bundle child volume";
         m_registry.MarkBundleChildRejected(dir);
         return false;
      }

      int childNo = cycle.bundleSubmittedChildren + 1;
      string comment = "BDR|C=" + (string)cycleKey +
                       "|G=" + (string)cycle.hedgeGeneration +
                       "|B=" + (string)cycle.bundleId +
                       "|N=" + (string)childNo;
      if(!ArmDurableCommand(dir, EXEC_CMD_RECOVERY_OPEN, m_cfg.recoveryMagic,
                            0, childUnits, RawRecoveryUnits(dir), 0.0,
                            cycle.hedgeGeneration, cycle.bundleId, why))
         return false;
      bool sent = exec.OpenMarketOwned(hedgeDir, volume,
                                       m_cfg.recoveryMagic, cycleKey,
                                       EXEC_CMD_RECOVERY_OPEN,
                                       EXEC_RECONCILE_FAIL_CLOSED,
                                       comment);
      if(!sent)
      {
         if(exec.HasReconcileRequired(cycleKey)) why = "child send outcome ambiguous; reconciliation required";
         else
         {
            CancelDurableCommand(dir);
            why = "child request rejected; bundle blocked pending explicit review/retry policy";
            m_registry.MarkBundleChildRejected(dir);
            m_dirty = true;
         }
         return false;
      }

      if(!m_registry.MarkBundleChildSubmitted(dir, childUnits))
      {
         why = "execution accepted child but registry could not mark it in-flight";
         return false;
      }
      m_dirty = true;
      string persistWhy = "";
      if(!SaveState(persistWhy))
      {
         why = "accepted bundle child could not be durably persisted: " + persistWhy;
         return false;
      }
      return true;
   }

   //--- T5 virtual hedge TP + realized ledger + Core close bridge ----------
   // Dormant until T9 removes ACTIVE fail-closed after persistence/reconcile.
   bool PrepareVirtualHedgeTp(const eRecoveryCoreDirection dir,
                              const EAContext &ctx,
                              string &why)
   {
      why = "";
      if(m_cfg.mode != recovery_ACTIVE)
      {
         why = "T5 exit bridge requires RecoveryMode=ACTIVE";
         return false;
      }
      SRecoveryCycle cycle;
      m_registry.GetCycle(dir, cycle);
      if(cycle.state != recovery_HEDGE_ACTIVE)
      {
         why = "cycle is not HEDGE_ACTIVE";
         return false;
      }
      EnsureT5Cycle(dir);

      SRecoveryCloseCandidate hedge[];
      long activeUnits = 0;
      double activeLots = 0.0, netBE = 0.0;
      if(!BuildRecoveryHedgeSnapshot(dir, hedge, activeUnits, activeLots, netBE))
      {
         why = "no valid active Recovery hedge snapshot/net breakeven";
         return false;
      }
      m_registry.ObserveHedgeMetrics(dir, activeLots, netBE);
      if(!Recovery_VirtualHedgeTpHit(dir, netBE, ctx.bid, ctx.ask, m_tpDistancePrice))
      {
         why = "virtual HedgeTP not reached";
         return false;
      }

      SRecoveryBundleVolumeMeta meta;
      if(!Recovery_ReadBundleVolumeMeta(_Symbol, meta, why)) return false;
      long target = Recovery_PartialCloseTargetUnits(activeUnits,
                                                      m_cfg.hedgePartialClosePercent,
                                                      meta.minUnits);
      if(target <= 0)
      {
         why = "configured hedge partial-close percentage is not executable on broker volume grid";
         return false;
      }
      SRecoveryCloseAction plan[];
      if(!Recovery_BuildHedgeClosePlan(hedge, target, meta.minUnits, plan, why)) return false;

      if(!m_registry.Transition(dir, recovery_HEDGE_TP_PENDING, ctx.now,
                                "soft HedgeTP reached; logical partial close started"))
      {
         why = "FSM rejected HEDGE_ACTIVE -> HEDGE_TP_PENDING";
         return false;
      }

      int idx = DirIndex(dir);
      m_t5[idx].tpLatched = true;
      m_t5[idx].hedgeCloseBaselineUnits = activeUnits;
      m_t5[idx].hedgeCloseTargetUnits = target;
      m_t5[idx].hedgeCloseObservedUnits = 0;
      m_t5[idx].hedgeNetBE = netBE;
      m_t5[idx].tpTriggerPrice = dir == recovery_CORE_BUY ? ctx.ask : ctx.bid;
      // Per-TP-window baselines are required once re-hedge creates G2+.
      // Ledger cash remains cumulative across the cycle; only unit evidence
      // is compared as a delta for this logical partial-close window.
      m_t5HedgeRealizedBaseline[idx] = m_t5[idx].ledger.hedgeRealizedCloseUnits;
      m_t6AnchorWeighted[idx] = 0.0;
      m_t6AnchorUnits[idx] = 0;
      m_t6RehedgeAnchorTicks[idx] = 0;
      m_t6LockTargetPrice[idx] = 0.0;
      return true;
   }

   bool RefreshHedgePartialClose(CExecutionLayer &exec,
                                 const eRecoveryCoreDirection dir,
                                 const datetime now,
                                 string &why)
   {
      why = "";
      if(m_cfg.mode != recovery_ACTIVE) return false;
      SRecoveryCycle cycle;
      m_registry.GetCycle(dir, cycle);
      if(cycle.state != recovery_HEDGE_TP_PENDING) return false;
      EnsureT5Cycle(dir);
      int idx = DirIndex(dir);
      int cycleKey = Recovery_CycleKey(dir);
      exec.ReconcileCycle(cycleKey);
      if(exec.HasReconcileRequired(cycleKey))
      {
         why = "hedge partial-close execution requires reconciliation";
         TransitionReconcile(dir, now, why);
         return false;
      }

      long currentUnits = ActiveRecoveryHedgeUnits(dir);
      long closedUnits = m_t5[idx].hedgeCloseBaselineUnits - currentUnits;
      if(closedUnits < 0 || closedUnits > m_t5[idx].hedgeCloseTargetUnits)
      {
         why = "broker-observed hedge close volume is outside exact T5 target";
         TransitionReconcile(dir, now, why);
         return false;
      }
      m_t5[idx].hedgeCloseObservedUnits = closedUnits;

      if(closedUnits == m_t5[idx].hedgeCloseTargetUnits && !exec.HasPendingForCycle(cycleKey))
      {
         long realizedUnits = m_t5[idx].ledger.hedgeRealizedCloseUnits -
                              m_t5HedgeRealizedBaseline[idx];
         if(realizedUnits < 0)
         {
            why = "T5 realized-unit baseline regressed";
            TransitionReconcile(dir, now, why);
            return false;
         }
         if(realizedUnits < closedUnits || m_t6AnchorUnits[idx] < closedUnits)
         {
            why = "broker volume changed but realized hedge deal/anchor evidence is not complete yet";
            return true;
         }
         if(realizedUnits > closedUnits || m_t6AnchorUnits[idx] > closedUnits)
         {
            why = "realized hedge close evidence exceeds broker-observed T5 target";
            TransitionReconcile(dir, now, why);
            return false;
         }
         long anchorTicks = Recovery_WeightedAnchorTicksPure(m_t6AnchorWeighted[idx],
                                                             m_t6AnchorUnits[idx],
                                                             m_tickSize);
         if(anchorTicks <= 0)
         {
            why = "confirmed hedge-close deals did not yield a valid re-hedge anchor";
            TransitionReconcile(dir, now, why);
            return false;
         }
         m_t6RehedgeAnchorTicks[idx] = anchorTicks;
         if(!m_registry.Transition(dir, recovery_CORE_CLOSE_PENDING, now,
                                   "hedge partial close and realized cash confirmed"))
         {
            why = "FSM rejected HEDGE_TP_PENDING -> CORE_CLOSE_PENDING";
            return false;
         }
      }
      return true;
   }

   bool SubmitNextHedgePartialClose(CExecutionLayer &exec,
                                    const eRecoveryCoreDirection dir,
                                    string &why)
   {
      why = "";
      if(m_cfg.mode != recovery_ACTIVE)
      {
         why = "T5 exit bridge requires RecoveryMode=ACTIVE";
         return false;
      }
      SRecoveryCycle cycle;
      m_registry.GetCycle(dir, cycle);
      if(cycle.state != recovery_HEDGE_TP_PENDING)
      {
         why = "cycle is not HEDGE_TP_PENDING";
         return false;
      }
      EnsureT5Cycle(dir);
      int idx = DirIndex(dir);
      int cycleKey = Recovery_CycleKey(dir);
      if(exec.HasReconcileRequired(cycleKey) || exec.HasPendingForCycle(cycleKey))
      {
         why = "cycle has pending/reconcile execution evidence";
         return false;
      }

      long remaining = m_t5[idx].hedgeCloseTargetUnits - m_t5[idx].hedgeCloseObservedUnits;
      if(remaining <= 0)
      {
         why = "hedge partial-close target already broker-observed; wait for realized evidence/refresh";
         return false;
      }

      SRecoveryCloseCandidate hedge[];
      long activeUnits = 0;
      double activeLots = 0.0, netBE = 0.0;
      if(!BuildRecoveryHedgeSnapshot(dir, hedge, activeUnits, activeLots, netBE))
      {
         why = "active Recovery hedge snapshot unavailable";
         return false;
      }
      SRecoveryBundleVolumeMeta meta;
      if(!Recovery_ReadBundleVolumeMeta(_Symbol, meta, why)) return false;
      SRecoveryCloseAction plan[];
      if(!Recovery_BuildHedgeClosePlan(hedge, remaining, meta.minUnits, plan, why))
      {
         TransitionReconcile(dir, TimeCurrent(), "remaining T5 hedge close target cannot be executed exactly");
         return false;
      }

      double volume = Recovery_UnitsToVolume(plan[0].units, meta.volumeStep);
      if(!ArmDurableCommand(dir, EXEC_CMD_RECOVERY_CLOSE, m_cfg.recoveryMagic,
                            plan[0].ticket, plan[0].units, RawRecoveryUnits(dir),
                            0.0, cycle.hedgeGeneration, cycle.bundleId, why))
         return false;
      bool sent = exec.ClosePositionVolumeOwned(plan[0].ticket, volume,
                                                m_cfg.recoveryMagic, cycleKey,
                                                EXEC_CMD_RECOVERY_CLOSE,
                                                EXEC_RECONCILE_FAIL_CLOSED);
      if(!sent && exec.HasReconcileRequired(cycleKey))
         TransitionReconcile(dir, TimeCurrent(), "ambiguous hedge partial-close outcome");
      if(!sent && !exec.HasReconcileRequired(cycleKey)) CancelDurableCommand(dir);
      if(!sent) why = exec.HasReconcileRequired(cycleKey) ?
                      "ambiguous hedge close; reconciliation required" :
                      "hedge close request rejected";
      return sent;
   }

   bool RefreshCoreClose(CExecutionLayer &exec,
                         const eRecoveryCoreDirection dir,
                         const datetime now,
                         string &why)
   {
      why = "";
      if(m_cfg.mode != recovery_ACTIVE) return false;
      SRecoveryCycle cycle;
      m_registry.GetCycle(dir, cycle);
      if(cycle.state != recovery_CORE_CLOSE_PENDING) return false;
      EnsureT5Cycle(dir);
      int idx = DirIndex(dir);
      int cycleKey = Recovery_CycleKey(dir);
      exec.ReconcileCycle(cycleKey);
      if(exec.HasReconcileRequired(cycleKey) || m_t5[idx].ledger.deficit)
      {
         why = exec.HasReconcileRequired(cycleKey) ?
               "Core partial-close execution requires reconciliation" :
               "actual Core realized loss exceeded confirmed hedge credit";
         TransitionReconcile(dir, now, why);
         return false;
      }
      if(exec.HasPendingForCycle(cycleKey)) return true;

      SRecoveryCloseCandidate core[];
      BuildCoreCloseCandidates(dir, core);
      SRecoveryBundleVolumeMeta meta;
      if(!Recovery_ReadBundleVolumeMeta(_Symbol, meta, why)) return false;
      SRecoveryCloseAction plan[];
      double estimate = 0.0;
      string planWhy = "";
      if(!Recovery_BuildCoreClosePlan(core, m_cfg.coreCloseMode,
                                      m_t5[idx].ledger.availableCredit,
                                      meta.minUnits, plan, estimate, planWhy))
      {
         if(!m_registry.Transition(dir, recovery_HEDGE_LOCK_PENDING, now,
                                   "no further legal Core loss close fits confirmed realized credit"))
         {
            why = "FSM rejected CORE_CLOSE_PENDING -> HEDGE_LOCK_PENDING";
            return false;
         }
         why = planWhy;
      }
      return true;
   }

   bool SubmitNextCoreClose(CExecutionLayer &exec,
                            const eRecoveryCoreDirection dir,
                            string &why)
   {
      why = "";
      if(m_cfg.mode != recovery_ACTIVE)
      {
         why = "T5 exit bridge requires RecoveryMode=ACTIVE";
         return false;
      }
      SRecoveryCycle cycle;
      m_registry.GetCycle(dir, cycle);
      if(cycle.state != recovery_CORE_CLOSE_PENDING)
      {
         why = "cycle is not CORE_CLOSE_PENDING";
         return false;
      }
      EnsureT5Cycle(dir);
      int idx = DirIndex(dir);
      int cycleKey = Recovery_CycleKey(dir);
      if(m_t5[idx].ledger.deficit || exec.HasReconcileRequired(cycleKey) || exec.HasPendingForCycle(cycleKey))
      {
         why = "credit deficit or execution evidence unresolved";
         return false;
      }

      SRecoveryCloseCandidate core[];
      BuildCoreCloseCandidates(dir, core);
      SRecoveryBundleVolumeMeta meta;
      if(!Recovery_ReadBundleVolumeMeta(_Symbol, meta, why)) return false;
      SRecoveryCloseAction plan[];
      double estimate = 0.0;
      if(!Recovery_BuildCoreClosePlan(core, m_cfg.coreCloseMode,
                                      m_t5[idx].ledger.availableCredit,
                                      meta.minUnits, plan, estimate, why))
         return false;

      double volume = Recovery_UnitsToVolume(plan[0].units, meta.volumeStep);
      if(!ArmDurableCommand(dir, EXEC_CMD_RECOVERY_CLOSE, (long)Magic,
                            plan[0].ticket, plan[0].units, CoreUnits(dir),
                            0.0, cycle.hedgeGeneration, cycle.bundleId, why))
         return false;
      bool sent = exec.ClosePositionVolumeOwned(plan[0].ticket, volume,
                                                (long)Magic, cycleKey,
                                                EXEC_CMD_RECOVERY_CLOSE,
                                                EXEC_RECONCILE_FAIL_CLOSED);
      if(!sent && exec.HasReconcileRequired(cycleKey))
         TransitionReconcile(dir, TimeCurrent(), "ambiguous Core partial-close outcome");
      if(!sent && !exec.HasReconcileRequired(cycleKey)) CancelDurableCommand(dir);
      if(!sent && why == "") why = "Core partial-close request rejected";
      return sent;
   }

   //--- T6 net-positive hedge lock + re-hedge bridge -----------------------
   // Dormant until T9 enables ACTIVE. Existing stronger broker SL is never
   // weakened. Each cycle still has at most one mutation command in flight.
   bool RefreshHedgeLock(CExecutionLayer &exec,
                         const eRecoveryCoreDirection dir,
                         const datetime now,
                         string &why)
   {
      why = "";
      if(m_cfg.mode != recovery_ACTIVE) return false;
      SRecoveryCycle cycle;
      m_registry.GetCycle(dir, cycle);
      if(cycle.state != recovery_HEDGE_LOCK_PENDING) return false;
      EnsureT5Cycle(dir);
      int idx = DirIndex(dir);
      int cycleKey = Recovery_CycleKey(dir);
      exec.ReconcileCycle(cycleKey);
      if(exec.HasReconcileRequired(cycleKey))
      {
         why = "hedge lock modification requires reconciliation";
         TransitionReconcile(dir, now, why);
         return false;
      }

      SRecoveryLockTicket tickets[];
      SRecoveryLockSnapshot snapshot;
      double targetSl = 0.0;
      if(!BuildT6LockPlan(dir, tickets, snapshot, targetSl, why))
      {
         TransitionReconcile(dir, now, "remaining Recovery hedge snapshot unavailable during required lock");
         return false;
      }
      m_t6LockTargetPrice[idx] = targetSl;
      m_registry.ObserveHedgeMetrics(dir, snapshot.activeLots, snapshot.netBE);
      if(exec.HasPendingForCycle(cycleKey)) return true;

      if(Recovery_FindWeakLockTicket(dir, tickets, targetSl, m_tickSize) >= 0)
      {
         why = "remaining hedge protection is not fully observable yet";
         return true;
      }
      if(m_t6RehedgeAnchorTicks[idx] <= 0)
      {
         why = "actual hedge partial-close deal anchor is unavailable";
         TransitionReconcile(dir, now, why);
         return false;
      }

      if(!m_registry.Transition(dir, recovery_HEDGE_LOCKED, now,
                                "all remaining Recovery hedge tickets have net-positive broker protection"))
      {
         why = "FSM rejected HEDGE_LOCK_PENDING -> HEDGE_LOCKED";
         return false;
      }
      return true;
   }

   bool SubmitNextHedgeLock(CExecutionLayer &exec,
                            const eRecoveryCoreDirection dir,
                            const EAContext &ctx,
                            string &why)
   {
      why = "";
      if(m_cfg.mode != recovery_ACTIVE)
      {
         why = "T6 lock bridge requires RecoveryMode=ACTIVE";
         return false;
      }
      SRecoveryCycle cycle;
      m_registry.GetCycle(dir, cycle);
      if(cycle.state != recovery_HEDGE_LOCK_PENDING)
      {
         why = "cycle is not HEDGE_LOCK_PENDING";
         return false;
      }
      EnsureT5Cycle(dir);
      int cycleKey = Recovery_CycleKey(dir);
      if(exec.HasReconcileRequired(cycleKey) || exec.HasPendingForCycle(cycleKey))
      {
         why = "cycle has pending/reconcile execution evidence";
         return false;
      }

      SRecoveryLockTicket tickets[];
      SRecoveryLockSnapshot snapshot;
      double targetSl = 0.0;
      if(!BuildT6LockPlan(dir, tickets, snapshot, targetSl, why)) return false;
      int weak = Recovery_FindWeakLockTicket(dir, tickets, targetSl, m_tickSize);
      if(weak < 0)
      {
         why = "all remaining Recovery hedge tickets already satisfy lock target";
         return false;
      }

      int stopsLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
      int freezeLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
      if(!Recovery_LockBrokerDistanceValidPure(dir, targetSl,
                                               ctx.bid, ctx.ask, ctx.point,
                                               stopsLevel, freezeLevel,
                                               m_tickSize))
      {
         why = "net-positive lock target is not currently placeable outside broker stops/freeze distance";
         return false;
      }

      if(!ArmDurableCommand(dir, EXEC_CMD_RECOVERY_MODIFY, m_cfg.recoveryMagic,
                            tickets[weak].ticket, 0, RawRecoveryUnits(dir),
                            targetSl, cycle.hedgeGeneration, cycle.bundleId, why))
         return false;
      bool sent = exec.ModifySlTpOwned(tickets[weak].ticket,
                                       targetSl,
                                       tickets[weak].tp,
                                       m_cfg.recoveryMagic,
                                       cycleKey,
                                       EXEC_CMD_RECOVERY_MODIFY,
                                       EXEC_RECONCILE_FAIL_CLOSED);
      if(!sent && exec.HasReconcileRequired(cycleKey))
         TransitionReconcile(dir, TimeCurrent(), "ambiguous Recovery hedge lock modification outcome");
      if(!sent && !exec.HasReconcileRequired(cycleKey)) CancelDurableCommand(dir);
      if(!sent && why == "") why = "Recovery hedge lock modification rejected";
      return sent;
   }

   bool EvaluateRehedge(const eRecoveryCoreDirection dir,
                        const EAContext &ctx,
                        string &why)
   {
      why = "";
      if(m_cfg.mode != recovery_ACTIVE)
      {
         why = "T6 re-hedge bridge requires RecoveryMode=ACTIVE";
         return false;
      }
      SRecoveryCycle cycle;
      m_registry.GetCycle(dir, cycle);
      if(cycle.state != recovery_HEDGE_LOCKED)
      {
         why = "cycle is not HEDGE_LOCKED";
         return false;
      }
      EnsureT5Cycle(dir);
      int idx = DirIndex(dir);
      if(!Recovery_GenerationCanStartPure(cycle.hedgeGeneration, m_cfg.maxHedgeGenerations))
      {
         // D-15: equality with Max blocks Max+1; it is not an automatic stop.
         why = "MaxHedgeGenerations_ reached; no further generation may start";
         return false;
      }
      if(m_t6RehedgeAnchorTicks[idx] <= 0)
      {
         why = "re-hedge anchor from confirmed hedge-close deal is unavailable";
         TransitionReconcile(dir, ctx.now, why);
         return false;
      }

      long bidTicks = Recovery_PriceToTicksPure(ctx.bid, m_tickSize);
      long askTicks = Recovery_PriceToTicksPure(ctx.ask, m_tickSize);
      if(!Recovery_RehedgeGapHitPure(dir, m_t6RehedgeAnchorTicks[idx],
                                     bidTicks, askTicks, m_rehedgeGapTicks))
      {
         why = "ReHedgeGapPips_ not reached from actual hedge-close anchor";
         return false;
      }

      long coreUnits = Recovery_CurrentCoreUnits(_Symbol, (long)Magic, dir, m_volumeStep);
      long activeHedgeUnits = ActiveRecoveryHedgeUnits(dir);
      long required = Recovery_RehedgeRequiredUnits(coreUnits, activeHedgeUnits);
      if(coreUnits <= 0)
      {
         why = "Core exposure is flat; no re-hedge is required";
         return false;
      }
      if(required <= 0)
      {
         why = "current Recovery hedge already covers Core exposure; deficit is zero";
         return false;
      }

      if(!m_registry.Transition(dir, recovery_REHEDGE_PENDING, ctx.now,
                                "actual close anchor moved by ReHedgeGap and exposure deficit exists"))
      {
         why = "FSM rejected HEDGE_LOCKED -> REHEDGE_PENDING";
         return false;
      }
      return true;
   }

   bool PrepareRehedgeBundle(const eRecoveryCoreDirection dir,
                             const datetime now,
                             string &why)
   {
      why = "";
      if(m_cfg.mode != recovery_ACTIVE)
      {
         why = "T6 re-hedge bridge requires RecoveryMode=ACTIVE";
         return false;
      }
      SRecoveryCycle cycle;
      m_registry.GetCycle(dir, cycle);
      if(cycle.state != recovery_REHEDGE_PENDING)
      {
         why = "cycle is not REHEDGE_PENDING";
         return false;
      }
      if(!Recovery_GenerationCanStartPure(cycle.hedgeGeneration, m_cfg.maxHedgeGenerations))
      {
         why = "starting the next logical hedge generation would exceed MaxHedgeGenerations_";
         return false;
      }

      long coreUnits = Recovery_CurrentCoreUnits(_Symbol, (long)Magic, dir, m_volumeStep);
      long activeHedgeUnits = ActiveRecoveryHedgeUnits(dir);
      long required = Recovery_RehedgeRequiredUnits(coreUnits, activeHedgeUnits);
      if(required <= 0)
      {
         why = "re-hedge exposure deficit is zero";
         return false;
      }

      SRecoveryBundleVolumeMeta meta;
      long children[];
      if(!BuildCurrentSplitPlan(dir, required, meta, children, why)) return false;
      return m_registry.BeginBundle(dir, required, activeHedgeUnits, now);
   }



   bool StartupReconcile(CExecutionLayer &exec, string &why)
   {
      why = "";
      if(m_cfg.mode != recovery_ACTIVE) return true;
      if(!m_initialized) { why = "RecoveryEngine is not initialized"; return false; }
      if(m_persistenceBlocked)
      {
         why = m_startupFaultReason == "" ? "Recovery persistence is corrupt/mismatched" : m_startupFaultReason;
         m_activeReady = false;
         return false;
      }

      bool ok = false;
      if(m_persistMissing)
         ok = FreshBootstrap(TimeCurrent(), why);
      else if(m_persistLoaded)
      {
         if(!ReplayDealsAfterCursor(why)) ok = false;
         else
         {
            string buyWhy = "", sellWhy = "";
            bool buyOk = ReconcileDirection(exec, recovery_CORE_BUY, TimeCurrent(), buyWhy);
            bool sellOk = ReconcileDirection(exec, recovery_CORE_SELL, TimeCurrent(), sellWhy);
            ok = buyOk && sellOk;
            if(!ok)
            {
               why = buyWhy;
               if(sellWhy != "") why = why == "" ? sellWhy : why + "; " + sellWhy;
            }
         }
      }
      else
      {
         why = "Recovery persistence load state is unresolved";
         ok = false;
      }

      if(!ok)
      {
         m_activeReady = false;
         return false;
      }
      m_activeReady = true;
      m_dirty = true;
      string saveWhy = "";
      if(!SaveState(saveWhy))
      {
         m_activeReady = false;
         why = "startup reconcile succeeded but durable save failed: " + saveWhy;
         return false;
      }
      Log_Info("Recovery", "T9 ACTIVE startup reconciliation complete; broker/history state is durable and execution is enabled");
      return true;
   }

   bool ActiveReady() const
   {
      return m_cfg.mode != recovery_ACTIVE || m_activeReady;
   }

   bool HasDurableCommand(const eRecoveryCoreDirection dir) const
   {
      return m_pending[DirIndex(dir)].active;
   }

   bool ArmDurableCommand(const eRecoveryCoreDirection dir,
                          const eExecCommandType commandType,
                          const long ownerMagic,
                          const ulong ticket,
                          const long targetUnits,
                          const long observedUnitsBefore,
                          const double targetPrice,
                          const int generation,
                          const int bundleId,
                          string &why)
   {
      why = "";
      if(m_cfg.mode != recovery_ACTIVE || m_persistenceBlocked)
      {
         why = "durable Recovery command cannot be recorded";
         return false;
      }
      int idx = DirIndex(dir);
      if(m_pending[idx].active)
      {
         why = "cycle already has a durable command in flight";
         return false;
      }
      if(commandType == EXEC_CMD_LEGACY || ownerMagic <= 0 || targetUnits < 0 || observedUnitsBefore < 0)
      {
         why = "invalid durable command metadata";
         return false;
      }
      m_pending[idx].active = true;
      m_pending[idx].cycleKey = Recovery_CycleKey(dir);
      m_pending[idx].commandType = commandType;
      m_pending[idx].ownerMagic = ownerMagic;
      m_pending[idx].ticket = ticket;
      m_pending[idx].targetUnits = targetUnits;
      m_pending[idx].observedUnitsBefore = observedUnitsBefore;
      m_pending[idx].targetPrice = targetPrice;
      m_pending[idx].startedAt = TimeCurrent();
      m_pending[idx].generation = generation;
      m_pending[idx].bundleId = bundleId;
      m_dirty = true;
      if(!SaveState(why))
      {
         Recovery_PendingInit(m_pending[idx]);
         m_activeReady = false;
         return false;
      }
      return true;
   }

   bool CancelDurableCommand(const eRecoveryCoreDirection dir)
   {
      if(m_cfg.mode != recovery_ACTIVE) return true;
      int idx = DirIndex(dir);
      Recovery_PendingInit(m_pending[idx]);
      m_dirty = true;
      string why = "";
      if(!SaveState(why))
      {
         Log_Error("Recovery", "cannot clear durable command: " + why);
         m_activeReady = false;
         return false;
      }
      return true;
   }

   bool ResolveDurableCommand(CExecutionLayer &exec,
                              const eRecoveryCoreDirection dir,
                              const datetime now,
                              string &why)
   {
      return ResolvePendingInternal(exec, dir, now, why);
   }

   bool FlushPersistence()
   {
      if(m_cfg.mode != recovery_ACTIVE || !m_dirty) return true;
      string why = "";
      if(!SaveState(why))
      {
         Log_Error("Recovery", "durable state flush failed: " + why);
         return false;
      }
      return true;
   }

   void RecordDealCursor(const ulong deal)
   {
      if(m_cfg.mode != recovery_ACTIVE || deal == 0 || !HistoryDealSelect(deal)) return;
      TrackSelectedDealCursor(deal);
   }

   bool DriveActive(CExecutionLayer &exec, const EAContext &ctx, string &why)
   {
      why = "";
      if(m_cfg.mode != recovery_ACTIVE || !m_activeReady) return false;
      string buyWhy = "", sellWhy = "";
      bool buyTerminal = DriveActiveDirection(exec, recovery_CORE_BUY, ctx, buyWhy);
      bool sellTerminal = DriveActiveDirection(exec, recovery_CORE_SELL, ctx, sellWhy);
      if(buyWhy != "") why = buyWhy;
      if(sellWhy != "") why = why == "" ? sellWhy : why + "; " + sellWhy;
      if(m_dirty) FlushPersistence();
      return buyTerminal || sellTerminal;
   }


   long RehedgeRequiredUnits(const eRecoveryCoreDirection dir) const
   {
      long coreUnits = Recovery_CurrentCoreUnits(_Symbol, (long)Magic, dir, m_volumeStep);
      return Recovery_RehedgeRequiredUnits(coreUnits, ActiveRecoveryHedgeUnits(dir));
   }

   long RehedgeAnchorTicks(const eRecoveryCoreDirection dir)
   {
      EnsureT5Cycle(dir);
      return m_t6RehedgeAnchorTicks[DirIndex(dir)];
   }

   double LockTargetPrice(const eRecoveryCoreDirection dir)
   {
      EnsureT5Cycle(dir);
      return m_t6LockTargetPrice[DirIndex(dir)];
   }

   void GetCycle(const eRecoveryCoreDirection dir, SRecoveryCycle &out) const
   {
      m_registry.GetCycle(dir, out);
   }

   void GetT5Runtime(const eRecoveryCoreDirection dir,
                     SRecoveryT5CycleRuntime &out)
   {
      EnsureT5Cycle(dir);
      out = m_t5[DirIndex(dir)];
   }

   int AuditStoredCount() const { return m_registry.AuditStoredCount(); }
   int AuditTotalCount() const  { return m_registry.AuditTotalCount(); }
};

#endif // BD_RECOVERY_ENGINE_MQH
