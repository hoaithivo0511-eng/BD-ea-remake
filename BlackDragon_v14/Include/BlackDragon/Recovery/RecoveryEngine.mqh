//+------------------------------------------------------------------+
//| RecoveryEngine.mqh — T3 SHADOW + T4 HedgeBundle foundation       |
//| Invariants: SHADOW sends NO trade request and never blocks Core. |
//|             T4 execution bridge is not wired into EA ACTIVE yet. |
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_ENGINE_MQH
#define BD_RECOVERY_ENGINE_MQH

#include <BlackDragon/Types.mqh>
#include <BlackDragon/Logger.mqh>
#include <BlackDragon/ExecutionLayer.mqh>
#include "RecoveryRegistry.mqh"

struct SRecoveryCorePositionSnapshot
{
   ulong    ticket;
   datetime openTime;
   double   openPrice;
   double   lots;
};

class CRecoveryEngine
{
private:
   CRecoveryRegistry          m_registry;
   SRecoveryFoundationConfig  m_cfg;
   bool                       m_initialized;
   double                     m_tickSize;
   double                     m_volumeStep;
   bool                       m_isGold;
   long                       m_gapTicks;

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
         p.ticket    = ticket;
         p.openTime  = (datetime)PositionGetInteger(POSITION_TIME);
         p.openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         p.lots      = PositionGetDouble(POSITION_VOLUME);

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

   long ActiveRecoveryHedgeUnits(const eRecoveryCoreDirection dir) const
   {
      if(m_volumeStep <= 0.0) return 0;
      long wantedType = Recovery_HedgeDirection(dir) == 0 ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
      long units = 0;
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
      if(!cycle.armed || cycle.state != recovery_ARMED ||
         cycle.shadowDecisionLatched)
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
                     "SHADOW hedge bundle blocked for " + Recovery_DirectionName(dir) +
                     ": " + planWhy);
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

public:
   CRecoveryEngine(void)
   {
      m_initialized = false;
      m_tickSize    = 0.0;
      m_volumeStep  = 0.0;
      m_isGold      = false;
      m_gapTicks    = 0;
   }

   bool Init()
   {
      Recovery_LoadFoundationConfig(m_cfg);
      m_registry.Init();
      m_initialized = false;

      if(m_cfg.mode == recovery_OFF)
      {
         m_initialized = true;
         return true;
      }

      if(m_cfg.mode == recovery_ACTIVE)
      {
         Log_Error("Recovery", "ACTIVE is not enabled in T4 HedgeBundle build — use SHADOW until ACTIVE wiring is complete");
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
         Log_Error("Recovery", "invalid T4 bundle volume metadata: " + volumeWhy);
         return false;
      }

      m_gapTicks = Recovery_PipsToTicksPure(m_cfg.hedgeGapPips, m_isGold,
                                            _Point, _Digits, m_tickSize);
      if(m_cfg.hedgeGapPips > 0.0 && m_gapTicks <= 0)
      {
         Log_Error("Recovery", "HedgeGapPips_ is not representable in symbol ticks");
         return false;
      }

      m_initialized = true;
      Log_Info("Recovery", "SHADOW registry/FSM + T4 smart-split enabled; no Recovery trade requests will be sent");
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
      if(!m_initialized || m_cfg.mode != recovery_SHADOW) return;
      if(trans.type != TRADE_TRANSACTION_DEAL_ADD || trans.deal == 0 ||
         trans.symbol != _Symbol || trans.position == 0)
         return;
      if(!HistoryDealSelect(trans.deal)) return;
      if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol ||
         HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != (long)Magic)
         return;

      long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_IN && entry != DEAL_ENTRY_INOUT) return;
      long type = HistoryDealGetInteger(trans.deal, DEAL_TYPE);
      eRecoveryCoreDirection dir;
      if(type == DEAL_TYPE_BUY) dir = recovery_CORE_BUY;
      else if(type == DEAL_TYPE_SELL) dir = recovery_CORE_SELL;
      else return;

      double price = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
      datetime dealTime = (datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME);
      m_registry.RecordCoreEntryEvidence(dir, trans.deal, trans.position, price, dealTime);
   }

   //--- T4 execution bridge -------------------------------------------------
   // These methods are deliberately NOT called by BlackDragon.mq5 in T4.
   // RecoveryMode must also be ACTIVE; T4 Init still rejects ACTIVE, so there
   // is no reachable trade path until the later ACTIVE-wiring gate is removed.
   bool PrepareInitialBundle(const eRecoveryCoreDirection dir,
                             const datetime now,
                             string &why)
   {
      why = "";
      if(m_cfg.mode != recovery_ACTIVE)
      {
         why = "T4 bundle execution bridge requires RecoveryMode=ACTIVE";
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
         why = "T4 bundle execution bridge requires RecoveryMode=ACTIVE";
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
      long existingDirectionalUnits = Recovery_DirectionalExposureUnits(_Symbol,
                                                                         hedgeDir,
                                                                         meta.volumeStep);
      if(!Recovery_VolumeLimitAllows(childUnits, existingDirectionalUnits,
                                     meta.volumeLimitUnits))
      {
         why = "next child would exceed current SYMBOL_VOLUME_LIMIT";
         m_registry.MarkBundleChildRejected(dir);
         return false;
      }
      if(!Recovery_ChildMarginPreflight(_Symbol, hedgeDir, childUnits,
                                        meta.volumeStep, why))
      {
         m_registry.MarkBundleChildRejected(dir);
         return false;
      }

      double volume = Recovery_UnitsToVolume(childUnits, meta.volumeStep);
      double normalized = Grid_NormalizeVolume(volume);
      if(MathAbs(normalized - volume) > meta.volumeStep * 1e-7)
      {
         why = "legacy execution normalization would alter exact T4 child volume";
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
         if(exec.HasReconcileRequired(cycleKey))
            why = "child send outcome ambiguous; reconciliation required";
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

   int AuditStoredCount() const { return m_registry.AuditStoredCount(); }
   int AuditTotalCount() const  { return m_registry.AuditTotalCount(); }
};

#endif // BD_RECOVERY_ENGINE_MQH
