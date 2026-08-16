//+------------------------------------------------------------------+
//| RecoveryEngine.mqh — T3 Registry/FSM + SHADOW evaluator          |
//| Invariants: SHADOW sends NO trade request and never blocks Core. |
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_ENGINE_MQH
#define BD_RECOVERY_ENGINE_MQH

#include <BlackDragon/Types.mqh>
#include <BlackDragon/Logger.mqh>
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
         // Recovery activation is Core-EA ownership only. Manual magic-0
         // remains a legacy BasketManager policy but cannot arm Recovery.
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

   void LogObservedStateChange(const eRecoveryCoreDirection dir,
                               const SRecoveryCycle &before,
                               const SRecoveryCycle &after)
   {
      if(before.state == after.state) return;
      Log_Info("Recovery", "SHADOW " + Recovery_DirectionName(dir) + " " +
               Recovery_StateName(before.state) + " -> " + Recovery_StateName(after.state));
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
         // Initial Core is index 0, therefore DCA N is oldest-sorted index N.
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
               // Do not guess an anchor from a stale/reconstructed basket in
               // T3. T9 owns restart/history reconciliation.
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
      if(m_registry.MarkShadowHedgeDecision(dir, targetUnits, triggerPrice, ctx.now))
      {
         string hedgeSide = Recovery_HedgeDirection(dir) == 0 ? "BUY" : "SELL";
         Log_Info("Recovery", "SHADOW would open " + hedgeSide + " hedge for " +
                  Recovery_DirectionName(dir) + " targetUnits=" + (string)targetUnits +
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

      // T3 is intentionally SHADOW-only. ACTIVE is fail-closed until the
      // later execution/persistence slices wire the full contract.
      if(m_cfg.mode == recovery_ACTIVE)
      {
         Log_Error("Recovery", "ACTIVE is not enabled in T3 Registry/FSM build — use SHADOW until ACTIVE wiring is complete");
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

      m_gapTicks = Recovery_PipsToTicksPure(m_cfg.hedgeGapPips, m_isGold,
                                            _Point, _Digits, m_tickSize);
      if(m_cfg.hedgeGapPips > 0.0 && m_gapTicks <= 0)
      {
         Log_Error("Recovery", "HedgeGapPips_ is not representable in symbol ticks");
         return false;
      }

      m_initialized = true;
      Log_Info("Recovery", "SHADOW registry/FSM enabled; no Recovery trade requests will be sent");
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

   // Transaction callback stays minimal: capture only confirmed inbound Core
   // evidence. Heavy state evaluation remains on OnTick.
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

   void GetCycle(const eRecoveryCoreDirection dir, SRecoveryCycle &out) const
   {
      m_registry.GetCycle(dir, out);
   }

   int AuditStoredCount() const { return m_registry.AuditStoredCount(); }
   int AuditTotalCount() const  { return m_registry.AuditTotalCount(); }
};

#endif // BD_RECOVERY_ENGINE_MQH
