from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def replace_once(rel, old, new):
    p = ROOT / rel
    s = p.read_text(encoding='utf-8')
    n = s.count(old)
    if n != 1:
        raise SystemExit(f'{rel}: expected one match, found {n}: {old[:80]!r}')
    p.write_text(s.replace(old, new, 1), encoding='utf-8')

ENGINE = 'BlackDragon_v14/Include/BlackDragon/Recovery/RecoveryEngine.mqh'
DCA = 'BlackDragon_v14/Include/BlackDragon/Recovery/RecoveryDca.mqh'
STRAT = 'BlackDragon_v14/Include/BlackDragon/Strategy.mqh'
ROOTEA = 'BlackDragon_v14/Experts/BlackDragon/BlackDragon.mq5'
COORD = 'BlackDragon_v14/Include/BlackDragon/Recovery/RecoveryExitCoordinator.mqh'

# ---------------------------------------------------------------------------
# RecoveryEngine: persistence, restart reconciliation, durable commands,
# common ACTIVE observation and one-entrypoint scheduler.
# ---------------------------------------------------------------------------
replace_once(ENGINE,
'''#include "RecoveryExit.mqh"\n#include "RecoveryLock.mqh"''',
'''#include "RecoveryExit.mqh"\n#include "RecoveryLock.mqh"\n#include "RecoveryPersistence.mqh"''')

replace_once(ENGINE,
'''   long                       m_rehedgeGapTicks;\n''',
'''   long                       m_rehedgeGapTicks;\n   CRecoveryPersistence       m_persistence;\n   SRecoveryPersistPending    m_pending[2];\n   bool                       m_activeReady;\n   bool                       m_persistLoaded;\n   bool                       m_persistMissing;\n   bool                       m_persistenceBlocked;\n   bool                       m_dirty;\n   long                       m_saveSequence;\n   ulong                      m_lastDealTicket;\n   long                       m_lastDealTimeMsc;\n   string                     m_startupFaultReason;\n''')

replace_once(ENGINE,
'''      m_registry.GetCycle(dir, cycle);\n      if(!cycle.armed || cycle.state != recovery_ARMED || cycle.shadowDecisionLatched)\n         return;\n''',
'''      m_registry.GetCycle(dir, cycle);\n      if(m_cfg.mode == recovery_ACTIVE &&\n         (before.state != cycle.state || before.coreCount != cycle.coreCount ||\n          MathAbs(before.coreLots - cycle.coreLots) > m_volumeStep * 1e-7))\n         m_dirty = true;\n\n      // ACTIVE uses the real T9 scheduler below. The remaining block is the\n      // T3 SHADOW decision path and must never latch a virtual decision in ACTIVE.\n      if(m_cfg.mode != recovery_SHADOW) return;\n      if(!cycle.armed || cycle.state != recovery_ARMED || cycle.shadowDecisionLatched)\n         return;\n''')

replace_once(ENGINE,
'''                  Log_Info("Recovery", "SHADOW " + Recovery_DirectionName(dir) +\n                           " armed at DCA=" + (string)dcaCount +''',
'''                  if(m_cfg.mode == recovery_ACTIVE) m_dirty = true;\n                  Log_Info("Recovery", (m_cfg.mode == recovery_ACTIVE ? "ACTIVE " : "SHADOW ") +\n                           Recovery_DirectionName(dir) +\n                           " armed at DCA=" + (string)dcaCount +''')

helper_block = r'''

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
'''

replace_once(ENGINE,
'''   bool TransitionReconcile(const eRecoveryCoreDirection dir,\n                            const datetime now,\n                            const string reason)\n   {\n      SRecoveryCycle c;\n      m_registry.GetCycle(dir, c);\n      if(c.state == recovery_RECONCILE_REQUIRED) return true;\n      return m_registry.Transition(dir, recovery_RECONCILE_REQUIRED, now, reason);\n   }\n\npublic:''',
'''   bool TransitionReconcile(const eRecoveryCoreDirection dir,\n                            const datetime now,\n                            const string reason)\n   {\n      SRecoveryCycle c;\n      m_registry.GetCycle(dir, c);\n      if(c.state == recovery_RECONCILE_REQUIRED) return true;\n      bool ok = m_registry.Transition(dir, recovery_RECONCILE_REQUIRED, now, reason);\n      if(ok && m_cfg.mode == recovery_ACTIVE) m_dirty = true;\n      return ok;\n   }''' + helper_block + '''\n\npublic:''')

replace_once(ENGINE,
'''      m_rehedgeGapTicks = 0;\n      m_seenWrite = 0;''',
'''      m_rehedgeGapTicks = 0;\n      m_activeReady = false;\n      m_persistLoaded = false;\n      m_persistMissing = false;\n      m_persistenceBlocked = false;\n      m_dirty = false;\n      m_saveSequence = 0;\n      m_lastDealTicket = 0;\n      m_lastDealTimeMsc = 0;\n      m_startupFaultReason = "";\n      Recovery_PendingInit(m_pending[0]);\n      Recovery_PendingInit(m_pending[1]);\n      m_seenWrite = 0;''')

replace_once(ENGINE,
'''      m_seenWrite = 0;\n      m_seenStored = 0;\n      for(int i = 0; i < BD_RECOVERY_T5_SEEN_DEALS; i++) m_seenDeals[i] = 0;\n      m_initialized = false;\n''',
'''      m_seenWrite = 0;\n      m_seenStored = 0;\n      for(int i = 0; i < BD_RECOVERY_T5_SEEN_DEALS; i++) m_seenDeals[i] = 0;\n      Recovery_PendingInit(m_pending[0]);\n      Recovery_PendingInit(m_pending[1]);\n      m_activeReady = false;\n      m_persistLoaded = false;\n      m_persistMissing = false;\n      m_persistenceBlocked = false;\n      m_dirty = false;\n      m_saveSequence = 0;\n      m_lastDealTicket = 0;\n      m_lastDealTimeMsc = 0;\n      m_startupFaultReason = "";\n      m_initialized = false;\n''')

replace_once(ENGINE,
'''      if(m_cfg.mode == recovery_ACTIVE)\n      {\n         Log_Error("Recovery", "ACTIVE is not enabled in T6 lock/re-hedge build — use SHADOW until T9 durable ACTIVE wiring");\n         return false;\n      }\n\n''', '')

replace_once(ENGINE,
'''      m_initialized = true;\n      Log_Info("Recovery", "SHADOW registry/FSM + smart-split + T5/T6 mechanics enabled; no Recovery trade requests will be sent");\n      return true;\n   }\n\n   void OnTick(const EAContext &ctx)\n   {\n      if(!m_initialized || m_cfg.mode != recovery_SHADOW) return;\n''',
'''      if(m_cfg.mode == recovery_ACTIVE)\n      {\n         m_persistence.Init(_Symbol, AccountInfoInteger(ACCOUNT_LOGIN),\n                            (long)Magic, m_cfg.recoveryMagic);\n         SRecoveryPersistPayload payload;\n         string loadWhy = "";\n         eRecoveryPersistLoadStatus st = m_persistence.Load(payload, loadWhy);\n         if(st == recovery_PERSIST_NOT_FOUND)\n            m_persistMissing = true;\n         else if(st == recovery_PERSIST_OK)\n         {\n            if(!Recovery_PersistPayloadIdentityValid(payload,\n                  AccountInfoInteger(ACCOUNT_LOGIN), Recovery_StringHash(_Symbol),\n                  (long)Magic, m_cfg.recoveryMagic, m_volumeStep, m_tickSize,\n                  m_cfg.startAfterDca) || !ImportPersistPayload(payload, loadWhy))\n            {\n               m_persistenceBlocked = true;\n               m_startupFaultReason = loadWhy == "" ? "Recovery state identity/config mismatch" : loadWhy;\n            }\n            else\n               m_persistLoaded = true;\n         }\n         else\n         {\n            m_persistenceBlocked = true;\n            m_startupFaultReason = loadWhy == "" ? "Recovery state integrity/I/O failure" : loadWhy;\n         }\n      }\n\n      m_initialized = true;\n      if(m_cfg.mode == recovery_SHADOW)\n         Log_Info("Recovery", "SHADOW registry/FSM + smart-split + T5/T6 mechanics enabled; no Recovery trade requests will be sent");\n      else\n         Log_Info("Recovery", "ACTIVE mechanics initialized; trading remains blocked until T9 startup reconciliation succeeds");\n      return true;\n   }\n\n   void OnTick(const EAContext &ctx)\n   {\n      if(!m_initialized || m_cfg.mode == recovery_OFF) return;\n      if(m_cfg.mode == recovery_ACTIVE && !m_activeReady) return;\n''')

# Replace OnTradeTransaction completely with cursor-aware version. Ledger math
# remains identical, but persistence is flushed after relevant deal evidence.
start = '''   void OnTradeTransaction(const MqlTradeTransaction &trans)\n   {\n      if(!m_initialized || m_cfg.mode == recovery_OFF) return;'''
end = '''   //--- T4 execution bridge -------------------------------------------------\n'''
p = ROOT / ENGINE
s = p.read_text(encoding='utf-8')
a = s.find(start)
b = s.find(end, a)
if a < 0 or b < 0:
    raise SystemExit('RecoveryEngine: cannot locate OnTradeTransaction block')
new_tx = r'''   void OnTradeTransaction(const MqlTradeTransaction &trans)
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

'''
p.write_text(s[:a] + new_tx + s[b:], encoding='utf-8')

# Durable pending before every strict engine mutation.
replace_once(ENGINE,
'''      bool sent = exec.OpenMarketOwned(hedgeDir, volume,\n                                       m_cfg.recoveryMagic, cycleKey,''',
'''      if(!ArmDurableCommand(dir, EXEC_CMD_RECOVERY_OPEN, m_cfg.recoveryMagic,\n                            0, childUnits, RawRecoveryUnits(dir), 0.0,\n                            cycle.hedgeGeneration, cycle.bundleId, why))\n         return false;\n      bool sent = exec.OpenMarketOwned(hedgeDir, volume,\n                                       m_cfg.recoveryMagic, cycleKey,''')
replace_once(ENGINE,
'''         else\n         {\n            why = "child request rejected; bundle blocked pending explicit review/retry policy";\n            m_registry.MarkBundleChildRejected(dir);\n         }\n         return false;\n      }\n\n      if(!m_registry.MarkBundleChildSubmitted(dir, childUnits))''',
'''         else\n         {\n            CancelDurableCommand(dir);\n            why = "child request rejected; bundle blocked pending explicit review/retry policy";\n            m_registry.MarkBundleChildRejected(dir);\n            m_dirty = true;\n         }\n         return false;\n      }\n\n      if(!m_registry.MarkBundleChildSubmitted(dir, childUnits))''')
replace_once(ENGINE,
'''      }\n      return true;\n   }\n\n   //--- T5 virtual hedge TP''',
'''      }\n      m_dirty = true;\n      string persistWhy = "";\n      if(!SaveState(persistWhy))\n      {\n         why = "accepted bundle child could not be durably persisted: " + persistWhy;\n         return false;\n      }\n      return true;\n   }\n\n   //--- T5 virtual hedge TP''')

replace_once(ENGINE,
'''      double volume = Recovery_UnitsToVolume(plan[0].units, meta.volumeStep);\n      bool sent = exec.ClosePositionVolumeOwned(plan[0].ticket, volume,\n                                                m_cfg.recoveryMagic, cycleKey,''',
'''      double volume = Recovery_UnitsToVolume(plan[0].units, meta.volumeStep);\n      if(!ArmDurableCommand(dir, EXEC_CMD_RECOVERY_CLOSE, m_cfg.recoveryMagic,\n                            plan[0].ticket, plan[0].units, RawRecoveryUnits(dir),\n                            0.0, cycle.hedgeGeneration, cycle.bundleId, why))\n         return false;\n      bool sent = exec.ClosePositionVolumeOwned(plan[0].ticket, volume,\n                                                m_cfg.recoveryMagic, cycleKey,''')
replace_once(ENGINE,
'''      if(!sent && exec.HasReconcileRequired(cycleKey))\n         TransitionReconcile(dir, TimeCurrent(), "ambiguous hedge partial-close outcome");\n      if(!sent) why = exec.HasReconcileRequired(cycleKey) ?\n                      "ambiguous hedge close; reconciliation required" :\n                      "hedge close request rejected";\n      return sent;''',
'''      if(!sent && exec.HasReconcileRequired(cycleKey))\n         TransitionReconcile(dir, TimeCurrent(), "ambiguous hedge partial-close outcome");\n      if(!sent && !exec.HasReconcileRequired(cycleKey)) CancelDurableCommand(dir);\n      if(!sent) why = exec.HasReconcileRequired(cycleKey) ?\n                      "ambiguous hedge close; reconciliation required" :\n                      "hedge close request rejected";\n      return sent;''')

replace_once(ENGINE,
'''      double volume = Recovery_UnitsToVolume(plan[0].units, meta.volumeStep);\n      bool sent = exec.ClosePositionVolumeOwned(plan[0].ticket, volume,\n                                                (long)Magic, cycleKey,''',
'''      double volume = Recovery_UnitsToVolume(plan[0].units, meta.volumeStep);\n      if(!ArmDurableCommand(dir, EXEC_CMD_RECOVERY_CLOSE, (long)Magic,\n                            plan[0].ticket, plan[0].units, CoreUnits(dir),\n                            0.0, cycle.hedgeGeneration, cycle.bundleId, why))\n         return false;\n      bool sent = exec.ClosePositionVolumeOwned(plan[0].ticket, volume,\n                                                (long)Magic, cycleKey,''')
replace_once(ENGINE,
'''      if(!sent && exec.HasReconcileRequired(cycleKey))\n         TransitionReconcile(dir, TimeCurrent(), "ambiguous Core partial-close outcome");\n      if(!sent && why == "") why = "Core partial-close request rejected";\n      return sent;''',
'''      if(!sent && exec.HasReconcileRequired(cycleKey))\n         TransitionReconcile(dir, TimeCurrent(), "ambiguous Core partial-close outcome");\n      if(!sent && !exec.HasReconcileRequired(cycleKey)) CancelDurableCommand(dir);\n      if(!sent && why == "") why = "Core partial-close request rejected";\n      return sent;''')

replace_once(ENGINE,
'''      bool sent = exec.ModifySlTpOwned(tickets[weak].ticket,\n                                       targetSl,''',
'''      if(!ArmDurableCommand(dir, EXEC_CMD_RECOVERY_MODIFY, m_cfg.recoveryMagic,\n                            tickets[weak].ticket, 0, RawRecoveryUnits(dir),\n                            targetSl, cycle.hedgeGeneration, cycle.bundleId, why))\n         return false;\n      bool sent = exec.ModifySlTpOwned(tickets[weak].ticket,\n                                       targetSl,''')
replace_once(ENGINE,
'''      if(!sent && exec.HasReconcileRequired(cycleKey))\n         TransitionReconcile(dir, TimeCurrent(), "ambiguous Recovery hedge lock modification outcome");\n      if(!sent && why == "") why = "Recovery hedge lock modification rejected";\n      return sent;''',
'''      if(!sent && exec.HasReconcileRequired(cycleKey))\n         TransitionReconcile(dir, TimeCurrent(), "ambiguous Recovery hedge lock modification outcome");\n      if(!sent && !exec.HasReconcileRequired(cycleKey)) CancelDurableCommand(dir);\n      if(!sent && why == "") why = "Recovery hedge lock modification rejected";\n      return sent;''')

# Add public T9 APIs before existing getters.
public_api = r'''

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
'''
replace_once(ENGINE,
'''   long RehedgeRequiredUnits(const eRecoveryCoreDirection dir) const\n   {''',
public_api + '''\n\n   long RehedgeRequiredUnits(const eRecoveryCoreDirection dir) const\n   {''')

# ---------------------------------------------------------------------------
# Recovery DCA + new-series startup gate.
# ---------------------------------------------------------------------------
replace_once(DCA,
'''      if(m_recovery == NULL || m_basket == NULL) return false;\n\n      eRecoveryCoreDirection recoveryDir =''',
'''      if(m_recovery == NULL || m_basket == NULL) return false;\n      if(!m_recovery.ActiveReady()) return false;\n\n      eRecoveryCoreDirection recoveryDir =''')

replace_once(DCA,
'''// Adapter into the existing Strategy grid-filter chain. It never opens a\n// hedge or a Core order and never mutates Recovery state. Recovery children\n// remain outside CBasketManager because they use RecoveryMagic_.\nclass CRecoveryDcaFilter''',
'''// ACTIVE startup gate for automated NEW SERIES. OFF/SHADOW are exact no-ops.\nclass CRecoveryStartupFilter : public IEntryFilter\n{\nprivate:\n   CRecoveryEngine *m_recovery;\npublic:\n   CRecoveryStartupFilter(CRecoveryEngine *recovery) { m_recovery = recovery; }\n   bool Allow(const EAContext &ctx, const int dir)\n   {\n      if(RecoveryMode_ != recovery_ACTIVE) return true;\n      return m_recovery != NULL && m_recovery.ActiveReady();\n   }\n};\n\n// Adapter into the existing Strategy grid-filter chain. It never opens a\n// hedge or a Core order and never mutates Recovery state. Recovery children\n// remain outside CBasketManager because they use RecoveryMagic_.\nclass CRecoveryDcaFilter''')

# ---------------------------------------------------------------------------
# Strategy: one RecoveryEngine pointer and one scheduler call after guards,
# before legacy exits. Existing T8 close ordering remains unchanged.
# ---------------------------------------------------------------------------
replace_once(STRAT,
'''   CDistancePlan     *m_dist;     // FE-407 (v14.7): classic or manual pip chain\n   CRecoveryExitCoordinator *m_recoveryExit; // T8: ACTIVE-only safety coordinator''',
'''   CDistancePlan     *m_dist;     // FE-407 (v14.7): classic or manual pip chain\n   CRecoveryEngine     *m_recovery;  // T9 ACTIVE scheduler/persistence gate\n   CRecoveryExitCoordinator *m_recoveryExit; // T8: ACTIVE-only safety coordinator''')

replace_once(STRAT,
'''   void Init(CBasketManager *basket, CExecutionLayer *exec, ILotSizer *sizer,\n             CMoneyGuard *guard, CDistancePlan *dist,\n             CRecoveryExitCoordinator *recoveryExit)\n   {\n      m_basket       = basket;\n      m_exec         = exec;\n      m_sizer        = sizer;\n      m_guard        = guard;\n      m_dist         = dist;\n      m_recoveryExit = recoveryExit;''',
'''   void Init(CBasketManager *basket, CExecutionLayer *exec, ILotSizer *sizer,\n             CMoneyGuard *guard, CDistancePlan *dist,\n             CRecoveryEngine *recovery, CRecoveryExitCoordinator *recoveryExit)\n   {\n      m_basket       = basket;\n      m_exec         = exec;\n      m_sizer        = sizer;\n      m_guard        = guard;\n      m_dist         = dist;\n      m_recovery     = recovery;\n      m_recoveryExit = recoveryExit;''')

replace_once(STRAT,
'''      // 2. Evaluate BOTH directions so simultaneous exits can both be sent,\n      //    then terminate before entries/real-level modifications.\n      bool exitBuy''',
'''      // T9: after account/global guard, drive the Recovery mutation chain\n      // before legacy Core exits. Stable states that do not trigger a mutation\n      // fall through; an accepted/in-flight mutation is terminal for this tick.\n      if(m_recovery != NULL && RecoveryMode_ == recovery_ACTIVE && m_recovery.ActiveReady())\n      {\n         string recoveryWhy = "";\n         if(m_recovery.DriveActive(*m_exec, ctx, recoveryWhy))\n         {\n            if(recoveryWhy != "")\n               Log_Warn("Recovery", "activedrive", "ACTIVE mutation chain: " + recoveryWhy);\n            if(panelOpenBuy || panelOpenSell)\n               Log_Warn("Recovery", "activewins", "panel open ignored because an ACTIVE Recovery mutation is in flight");\n            return;\n         }\n      }\n\n      // 2. Evaluate BOTH directions so simultaneous exits can both be sent,\n      //    then terminate before entries/real-level modifications.\n      bool exitBuy''')

# ---------------------------------------------------------------------------
# T8 coordinator: persist strict cleanup command before send when ACTIVE is
# reconciled. If ACTIVE startup is already blocked, risk-reducing cleanup keeps
# the existing T8 behavior without creating new exposure.
# ---------------------------------------------------------------------------
replace_once(COORD,
'''      double volume = Recovery_UnitsToVolume(requestUnits, step);\n      int cycleKey = Recovery_CycleKey(dir);\n      bool sent = m_exec.ClosePositionVolumeOwned(ticket, volume,''',
'''      double volume = Recovery_UnitsToVolume(requestUnits, step);\n      int cycleKey = Recovery_CycleKey(dir);\n      bool durable = m_recovery != NULL && m_recovery.ActiveReady();\n      if(durable && !m_recovery.ArmDurableCommand(dir, EXEC_CMD_RECOVERY_CLOSE,\n                                                   (long)RecoveryMagic_, ticket,\n                                                   requestUnits, RecoveryUnits(dir),\n                                                   0.0, 0, 0, why))\n         return false;\n      bool sent = m_exec.ClosePositionVolumeOwned(ticket, volume,''')
replace_once(COORD,
'''         why = m_exec.HasReconcileRequired(cycleKey) ?\n               "Recovery cleanup hedge close is ambiguous; reconciliation required" :\n               "Recovery cleanup hedge close request was rejected";\n         m_cycle[idx].active = false;''',
'''         if(durable && !m_exec.HasReconcileRequired(cycleKey))\n            m_recovery.CancelDurableCommand(dir);\n         why = m_exec.HasReconcileRequired(cycleKey) ?\n               "Recovery cleanup hedge close is ambiguous; reconciliation required" :\n               "Recovery cleanup hedge close request was rejected";\n         m_cycle[idx].active = false;''')

replace_once(COORD,
'''         int cycleKey = Recovery_CycleKey(Direction(idx));\n         bool sent = m_exec.ClosePositionVolumeOwned(ticket, volume,''',
'''         eRecoveryCoreDirection dir = Direction(idx);\n         int cycleKey = Recovery_CycleKey(dir);\n         long units = VolumeStepUnits(volume);\n         bool durable = m_recovery != NULL && m_recovery.ActiveReady();\n         if(durable && !m_recovery.ArmDurableCommand(dir, EXEC_CMD_RECOVERY_CLOSE,\n                                                      (long)Magic, ticket, units,\n                                                      CoreMagicUnits(dir), 0.0,\n                                                      0, 0, why))\n            return false;\n         bool sent = m_exec.ClosePositionVolumeOwned(ticket, volume,''')
replace_once(COORD,
'''         if(!sent)\n         {\n            why = m_exec.HasReconcileRequired(cycleKey) ?''',
'''         if(!sent)\n         {\n            if(durable && !m_exec.HasReconcileRequired(cycleKey))\n               m_recovery.CancelDurableCommand(dir);\n            why = m_exec.HasReconcileRequired(cycleKey) ?''')

replace_once(COORD,
'''      eRecoveryCoreDirection dir = Direction(idx);\n      int cycleKey = Recovery_CycleKey(dir);\n      m_exec.ReconcileCycle(cycleKey);''',
'''      eRecoveryCoreDirection dir = Direction(idx);\n      int cycleKey = Recovery_CycleKey(dir);\n      if(m_recovery != NULL && m_recovery.ActiveReady() && m_recovery.HasDurableCommand(dir))\n      {\n         string durableWhy = "";\n         if(!m_recovery.ResolveDurableCommand(*m_exec, dir, now, durableWhy))\n         {\n            m_cycle[idx].active = false;\n            m_cycle[idx].reconcileHold = true;\n            why = durableWhy;\n            return true;\n         }\n      }\n      m_exec.ReconcileCycle(cycleKey);''')

# ---------------------------------------------------------------------------
# Composition root: startup reconcile after execution initialization, startup
# entry filter, persistence flush/cursor, and updated Strategy signature.
# ---------------------------------------------------------------------------
replace_once(ROOTEA,
'''   g_exec.Init();\n   g_recoveryExit.Init(&g_recovery, &g_exec); // inert in OFF/SHADOW; ACTIVE remains gated until T9\n''',
'''   g_exec.Init();\n   if(RecoveryMode_ == recovery_ACTIVE)\n   {\n      string startupWhy = "";\n      if(!g_recovery.StartupReconcile(g_exec, startupWhy))\n         Log_Error("Recovery", "ACTIVE startup is FAIL-CLOSED: " + startupWhy);\n   }\n   g_recoveryExit.Init(&g_recovery, &g_exec); // T8 cleanup; T9 ACTIVE may now be reconciled\n''')
replace_once(ROOTEA,
'''   g_strategy.Init(&g_basket, &g_exec, sizer, &g_guard, &g_distPlan, &g_recoveryExit);''',
'''   g_strategy.Init(&g_basket, &g_exec, sizer, &g_guard, &g_distPlan,\n                   &g_recovery, &g_recoveryExit);''')
replace_once(ROOTEA,
'''   g_strategy.AddNewSeriesFilter(new CHaltFilter(&g_guard));\n   g_strategy.AddGridFilter(new CHaltFilter(&g_guard));''',
'''   g_strategy.AddNewSeriesFilter(new CRecoveryStartupFilter(&g_recovery));\n   g_strategy.AddNewSeriesFilter(new CHaltFilter(&g_guard));\n   g_strategy.AddGridFilter(new CHaltFilter(&g_guard));''')
replace_once(ROOTEA,
'''   EventKillTimer();\n   Persist_Save();''',
'''   EventKillTimer();\n   g_recovery.FlushPersistence();\n   Persist_Save();''')
replace_once(ROOTEA,
'''   g_exec.Watchdog();           // async journal reconciliation (Nhom B)\n   // T8: process broker/manual exit cleanup''',
'''   g_exec.Watchdog();           // async journal reconciliation (Nhom B)\n   g_recovery.FlushPersistence(); // T9: transition/deal-driven durable state only\n   // T8: process broker/manual exit cleanup''')
replace_once(ROOTEA,
'''   bool suppressRecoveryDeal = g_recoveryExit.OnTradeTransaction(trans);\n   if(!suppressRecoveryDeal)\n      g_recovery.OnTradeTransaction(trans);''',
'''   bool suppressRecoveryDeal = g_recoveryExit.OnTradeTransaction(trans);\n   if(!suppressRecoveryDeal)\n      g_recovery.OnTradeTransaction(trans);\n   else if(trans.type == TRADE_TRANSACTION_DEAL_ADD && trans.deal != 0)\n   {\n      g_recovery.RecordDealCursor(trans.deal);\n      g_recovery.FlushPersistence();\n   }''')

print('T9 patch applied')
