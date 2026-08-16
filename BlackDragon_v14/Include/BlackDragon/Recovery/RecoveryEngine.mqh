//+------------------------------------------------------------------+
//| RecoveryEngine.mqh — T3 SHADOW + T4 bundle + T5 exit mechanics   |
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
   ulong                      m_seenDeals[BD_RECOVERY_T5_SEEN_DEALS];
   int                        m_seenWrite;
   int                        m_seenStored;
   bool                       m_initialized;
   double                     m_tickSize;
   double                     m_volumeStep;
   bool                       m_isGold;
   long                       m_gapTicks;
   double                     m_tpDistancePrice;

   int DirIndex(const eRecoveryCoreDirection dir) const
   {
      return dir == recovery_CORE_BUY ? 0 : 1;
   }

   void EnsureT5Cycle(const eRecoveryCoreDirection dir)
   {
      int idx = DirIndex(dir);
      SRecoveryCycle cycle;
      m_registry.GetCycle(dir, cycle);
      if(m_t5CycleSerial[idx] == cycle.cycleSerial) return;
      Recovery_T5RuntimeInit(m_t5[idx]);
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
                  Log_Info("Recovery", "SHADOW " + Recovery_DirectionName(dir) +
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
      return m_registry.Transition(dir, recovery_RECONCILE_REQUIRED, now, reason);
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
      m_seenWrite = 0;
      m_seenStored = 0;
      m_t5CycleSerial[0] = 0;
      m_t5CycleSerial[1] = 0;
      Recovery_T5RuntimeInit(m_t5[0]);
      Recovery_T5RuntimeInit(m_t5[1]);
      for(int i = 0; i < BD_RECOVERY_T5_SEEN_DEALS; i++) m_seenDeals[i] = 0;
   }

   bool Init()
   {
      Recovery_LoadFoundationConfig(m_cfg);
      m_registry.Init();
      Recovery_T5RuntimeInit(m_t5[0]);
      Recovery_T5RuntimeInit(m_t5[1]);
      m_t5CycleSerial[0] = 1;
      m_t5CycleSerial[1] = 1;
      m_seenWrite = 0;
      m_seenStored = 0;
      for(int i = 0; i < BD_RECOVERY_T5_SEEN_DEALS; i++) m_seenDeals[i] = 0;
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

      if(m_cfg.mode == recovery_ACTIVE)
      {
         Log_Error("Recovery", "ACTIVE is not enabled in T5 exit-mechanics build — use SHADOW until T9 durable ACTIVE wiring");
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

      m_initialized = true;
      Log_Info("Recovery", "SHADOW registry/FSM + smart-split + T5 exit planning enabled; no Recovery trade requests will be sent");
      return true;
   }

   void OnTick(const EAContext &ctx)
   {
      if(!m_initialized || m_cfg.mode != recovery_SHADOW) return;

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

      // T3 arming evidence remains available in SHADOW and later ACTIVE.
      if(magic == (long)Magic && (entry == DEAL_ENTRY_IN || entry == DEAL_ENTRY_INOUT))
      {
         eRecoveryCoreDirection dir;
         if(type == DEAL_TYPE_BUY) dir = recovery_CORE_BUY;
         else if(type == DEAL_TYPE_SELL) dir = recovery_CORE_SELL;
         else return;
         ulong position = trans.position;
         if(position == 0) position = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
         double price = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
         datetime dealTime = (datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME);
         m_registry.RecordCoreEntryEvidence(dir, trans.deal, position, price, dealTime);
         return;
      }

      // T5 ledger path is intentionally dormant while ACTIVE init is blocked.
      if(m_cfg.mode != recovery_ACTIVE) return;
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY) return;
      if(DealSeen(trans.deal)) return;

      double cash = Recovery_DealCashPure(HistoryDealGetDouble(trans.deal, DEAL_PROFIT),
                                          HistoryDealGetDouble(trans.deal, DEAL_SWAP),
                                          HistoryDealGetDouble(trans.deal, DEAL_COMMISSION),
                                          HistoryDealGetDouble(trans.deal, DEAL_FEE));

      if(magic == m_cfg.recoveryMagic)
      {
         eRecoveryCoreDirection dir;
         if(type == DEAL_TYPE_BUY) dir = recovery_CORE_BUY;       // closes SELL recovery hedge
         else if(type == DEAL_TYPE_SELL) dir = recovery_CORE_SELL;// closes BUY recovery hedge
         else return;
         SRecoveryCycle cycle;
         m_registry.GetCycle(dir, cycle);
         if(cycle.state != recovery_HEDGE_TP_PENDING) return;
         EnsureT5Cycle(dir);
         long actualUnits = Recovery_VolumeToUnitsFloor(HistoryDealGetDouble(trans.deal, DEAL_VOLUME), m_volumeStep);
         Recovery_LedgerApplyHedgeDeal(m_t5[DirIndex(dir)].ledger, cash, actualUnits);
         MarkDealSeen(trans.deal);
         return;
      }

      if(magic == (long)Magic)
      {
         eRecoveryCoreDirection dir;
         if(type == DEAL_TYPE_SELL) dir = recovery_CORE_BUY;      // closes BUY Core
         else if(type == DEAL_TYPE_BUY) dir = recovery_CORE_SELL; // closes SELL Core
         else return;
         SRecoveryCycle cycle;
         m_registry.GetCycle(dir, cycle);
         if(cycle.state != recovery_CORE_CLOSE_PENDING) return;
         EnsureT5Cycle(dir);
         Recovery_LedgerApplyCoreDeal(m_t5[DirIndex(dir)].ledger, cash);
         MarkDealSeen(trans.deal);
      }
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
            why = "child request rejected; bundle blocked pending explicit review/retry policy";
            m_registry.MarkBundleChildRejected(dir);
         }
         return false;
      }

      if(!m_registry.MarkBundleChildSubmitted(dir, childUnits))
      {
         why = "execution accepted child but registry could not mark it in-flight";
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
         long realizedUnits = m_t5[idx].ledger.hedgeRealizedCloseUnits;
         if(realizedUnits < closedUnits)
         {
            why = "broker volume changed but realized hedge deal evidence is not complete yet";
            return true;
         }
         if(realizedUnits > closedUnits)
         {
            why = "realized hedge close units exceed broker-observed T5 target";
            TransitionReconcile(dir, now, why);
            return false;
         }
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
      bool sent = exec.ClosePositionVolumeOwned(plan[0].ticket, volume,
                                                m_cfg.recoveryMagic, cycleKey,
                                                EXEC_CMD_RECOVERY_CLOSE,
                                                EXEC_RECONCILE_FAIL_CLOSED);
      if(!sent && exec.HasReconcileRequired(cycleKey))
         TransitionReconcile(dir, TimeCurrent(), "ambiguous hedge partial-close outcome");
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
      bool sent = exec.ClosePositionVolumeOwned(plan[0].ticket, volume,
                                                (long)Magic, cycleKey,
                                                EXEC_CMD_RECOVERY_CLOSE,
                                                EXEC_RECONCILE_FAIL_CLOSED);
      if(!sent && exec.HasReconcileRequired(cycleKey))
         TransitionReconcile(dir, TimeCurrent(), "ambiguous Core partial-close outcome");
      if(!sent && why == "") why = "Core partial-close request rejected";
      return sent;
   }

   long RehedgeRequiredUnits(const eRecoveryCoreDirection dir) const
   {
      SRecoveryCycle cycle;
      m_registry.GetCycle(dir, cycle);
      long coreUnits = Recovery_VolumeToUnitsFloor(cycle.coreLots, m_volumeStep);
      return Recovery_RehedgeRequiredUnits(coreUnits, ActiveRecoveryHedgeUnits(dir));
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
