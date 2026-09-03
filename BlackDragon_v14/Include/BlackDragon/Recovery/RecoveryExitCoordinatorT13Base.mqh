//+------------------------------------------------------------------+
//| RecoveryExitCoordinator.mqh — T8 legacy-exit safety coordinator  |
//| Purpose   : keep Recovery hedge exposure cycle-safe when legacy  |
//|             Core exits, MoneyGuard or operator/broker exits occur.|
//| Invariants: no OrderSend here; all mutations use ExecutionLayer. |
//|             OFF/SHADOW are strict no-ops.                        |
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_EXIT_COORDINATOR_MQH
#define BD_RECOVERY_EXIT_COORDINATOR_MQH

#include "RecoveryEngine.mqh"
#include "RecoveryGlobalFlatten.mqh"
#include "RecoveryMutationPolicy.mqh"
#include <BlackDragon/BasketManager.mqh>

enum eRecoveryExitCoordKind
{
   recovery_EXIT_COORD_NONE = 0,
   recovery_EXIT_COORD_FULL_SIDE,
   recovery_EXIT_COORD_TICKETS,
   recovery_EXIT_COORD_EXTERNAL
};

enum eRecoveryExitCoordReason
{
   recovery_EXIT_REASON_NONE = 0,
   recovery_EXIT_REASON_RETIRED_CHART_CONTROL = 1,
   recovery_EXIT_REASON_LEGACY_TP = 2,
   recovery_EXIT_REASON_LEGACY_SL = 3,
   recovery_EXIT_REASON_LEGACY_TRAIL = 4,
   recovery_EXIT_REASON_LEGACY_OVERLAP = 5,
   recovery_EXIT_REASON_GUARD_SIDE = 6,
   recovery_EXIT_REASON_GUARD_MAGIC = 7,
   recovery_EXIT_REASON_GUARD_DAILY = 8,
   recovery_EXIT_REASON_EXTERNAL_CORE = 9,
   recovery_EXIT_REASON_EXTERNAL_RECOVERY = 10
};

enum eRecoveryExitCoordRequest
{
   recovery_EXIT_BYPASS = 0,
   recovery_EXIT_LATCHED,
   recovery_EXIT_BLOCKED
};

enum eRecoveryExitCoordStep
{
   recovery_EXIT_STEP_NONE = 0,
   recovery_EXIT_STEP_TRIM_HEDGE,
   recovery_EXIT_STEP_CLOSE_CORE,
   recovery_EXIT_STEP_COMPLETE,
   recovery_EXIT_STEP_RECONCILE_HOLD
};

struct SRecoveryExitCoordCycle
{
   bool                     active;
   bool                     reconcileHold;
   eRecoveryExitCoordKind   kind;
   eRecoveryExitCoordReason reason;
   long                     targetCoreUnits;
   ulong                    ticketFirst;
   ulong                    ticketSecond;
   int                      ticketCount;
   ulong                    legacyPendingTicket;
   datetime                 startedAt;
};

bool Recovery_ExitStateNeedsCoordination(const eRecoveryState state)
{
   // T13: once ARMED, any Core topology mutation belongs to Recovery lifecycle.
   return state != recovery_CORE_ONLY &&
          state != recovery_COMPLETED;
}

long Recovery_ExitPostCoreUnits(const long currentCoreUnits,
                                const long intendedCoreCloseUnits)
{
   if(currentCoreUnits <= 0) return 0;
   if(intendedCoreCloseUnits <= 0) return currentCoreUnits;
   return intendedCoreCloseUnits >= currentCoreUnits ? 0 :
          currentCoreUnits - intendedCoreCloseUnits;
}

long Recovery_ExitHedgeCapUnits(const long currentCoreUnits,
                                const long targetCoreUnits,
                                const bool externalMutation)
{
   long current = currentCoreUnits > 0 ? currentCoreUnits : 0;
   if(externalMutation) return current;
   long target = targetCoreUnits > 0 ? targetCoreUnits : 0;
   return current < target ? current : target;
}

long Recovery_ExitExcessHedgeUnits(const long currentCoreUnits,
                                   const long targetCoreUnits,
                                   const long activeHedgeUnits,
                                   const bool externalMutation)
{
   if(activeHedgeUnits <= 0) return 0;
   long cap = Recovery_ExitHedgeCapUnits(currentCoreUnits, targetCoreUnits,
                                         externalMutation);
   return activeHedgeUnits > cap ? activeHedgeUnits - cap : 0;
}

long Recovery_ExitTrimRequestUnits(const long excessUnits,
                                   const long selectedTicketUnits,
                                   const long minUnits)
{
   if(excessUnits <= 0 || selectedTicketUnits <= 0 || minUnits <= 0) return 0;
   // If the exact residual is below broker minimum, close one complete child.
   // This may under-cover Core by a bounded amount but never leaves known
   // over-hedge/naked Recovery exposure during an exit chain.
   if(excessUnits < minUnits) return selectedTicketUnits;
   return excessUnits < selectedTicketUnits ? excessUnits : selectedTicketUnits;
}

bool Recovery_ExitExternalDealReason(const long dealReason)
{
   return dealReason != DEAL_REASON_EXPERT;
}

// T10 runtime regression: a broker-side SL can be an EXPECTED Recovery event
// when it is the net-positive protective lock placed by T6. Treating every
// non-EXPERT close as external made those expected SL fills latch T8 into an
// indefinite reconciliation hold. Keep this helper pure so the classification
// can be regression-tested independently from broker history plumbing.
bool Recovery_ExitExpectedLockSlPure(const eRecoveryState state,
                                     const long dealReason,
                                     const double dealPrice,
                                     const double targetSl,
                                     const double tolerance)
{
   if(dealReason != DEAL_REASON_SL) return false;
   if(state != recovery_HEDGE_LOCK_PENDING && state != recovery_HEDGE_LOCKED)
      return false;
   if(dealPrice <= 0.0 || targetSl <= 0.0 || tolerance < 0.0) return false;
   return MathAbs(dealPrice - targetSl) <= tolerance + 1e-12;
}

eRecoveryExitCoordStep Recovery_ExitNextStepPure(const bool externalMutation,
                                                 const long currentCoreUnits,
                                                 const long targetCoreUnits,
                                                 const long activeHedgeUnits,
                                                 const bool intendedManagedTicketLive)
{
   if(Recovery_ExitExcessHedgeUnits(currentCoreUnits, targetCoreUnits,
                                    activeHedgeUnits, externalMutation) > 0)
      return recovery_EXIT_STEP_TRIM_HEDGE;

   if(externalMutation)
   {
      if(currentCoreUnits <= 0 && activeHedgeUnits <= 0)
         return recovery_EXIT_STEP_COMPLETE;
      return recovery_EXIT_STEP_RECONCILE_HOLD;
   }

   if(intendedManagedTicketLive || currentCoreUnits > targetCoreUnits)
      return recovery_EXIT_STEP_CLOSE_CORE;

   if(activeHedgeUnits > currentCoreUnits)
      return recovery_EXIT_STEP_TRIM_HEDGE;
   return recovery_EXIT_STEP_COMPLETE;
}

class CRecoveryExitCoordinator
{
private:
   CRecoveryEngine          *m_recovery;
   CExecutionLayer          *m_exec;
   SRecoveryExitCoordCycle   m_cycle[2];
   bool                      m_accountWidePending;
   datetime                  m_accountWideStartedAt;

   int Index(const eRecoveryCoreDirection dir) const
   {
      return dir == recovery_CORE_BUY ? 0 : 1;
   }

   eRecoveryCoreDirection Direction(const int idx) const
   {
      return idx == 0 ? recovery_CORE_BUY : recovery_CORE_SELL;
   }

   long CorePositionType(const eRecoveryCoreDirection dir) const
   {
      return dir == recovery_CORE_BUY ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   }

   long RecoveryPositionType(const eRecoveryCoreDirection dir) const
   {
      return dir == recovery_CORE_BUY ? POSITION_TYPE_SELL : POSITION_TYPE_BUY;
   }

   void ResetCycle(const int idx)
   {
      m_cycle[idx].active              = false;
      m_cycle[idx].reconcileHold       = false;
      m_cycle[idx].kind                = recovery_EXIT_COORD_NONE;
      m_cycle[idx].reason              = recovery_EXIT_REASON_NONE;
      m_cycle[idx].targetCoreUnits     = 0;
      m_cycle[idx].ticketFirst         = 0;
      m_cycle[idx].ticketSecond        = 0;
      m_cycle[idx].ticketCount         = 0;
      m_cycle[idx].legacyPendingTicket = 0;
      m_cycle[idx].startedAt           = 0;
   }

   long VolumeStepUnits(const double volume) const
   {
      double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      return Recovery_VolumeToUnitsFloor(volume, step);
   }

   long CoreMagicUnits(const eRecoveryCoreDirection dir) const
   {
      long units = 0;
      long wanted = CorePositionType(dir);
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol ||
            PositionGetInteger(POSITION_MAGIC) != (long)Magic ||
            PositionGetInteger(POSITION_TYPE) != wanted)
            continue;
         units += VolumeStepUnits(PositionGetDouble(POSITION_VOLUME));
      }
      return units;
   }

   long RecoveryUnits(const eRecoveryCoreDirection dir) const
   {
      long units = 0;
      long wanted = RecoveryPositionType(dir);
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol ||
            PositionGetInteger(POSITION_MAGIC) != (long)RecoveryMagic_ ||
            PositionGetInteger(POSITION_TYPE) != wanted)
            continue;
         units += VolumeStepUnits(PositionGetDouble(POSITION_VOLUME));
      }
      return units;
   }

   bool IsLegacyManagedMagic(const long magic) const
   {
      return Basket_OwnsMagic(magic, (long)Magic, flag_Hand_Ord);
   }

   bool SelectOldestManagedSideTicket(const eRecoveryCoreDirection dir,
                                      ulong &ticketOut,
                                      long &ownerMagicOut) const
   {
      ticketOut = 0;
      ownerMagicOut = 0;
      datetime bestTime = 0;
      long wanted = CorePositionType(dir);
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol ||
            PositionGetInteger(POSITION_TYPE) != wanted)
            continue;
         long magic = PositionGetInteger(POSITION_MAGIC);
         if(!IsLegacyManagedMagic(magic)) continue;
         datetime t = (datetime)PositionGetInteger(POSITION_TIME);
         if(ticketOut == 0 || t < bestTime || (t == bestTime && ticket < ticketOut))
         {
            ticketOut = ticket;
            ownerMagicOut = magic;
            bestTime = t;
         }
      }
      return ticketOut != 0;
   }

   bool SelectRecoveryTrimTicket(const eRecoveryCoreDirection dir,
                                 const long excessUnits,
                                 const long minUnits,
                                 ulong &ticketOut,
                                 long &ticketUnitsOut) const
   {
      ticketOut = 0;
      ticketUnitsOut = 0;
      long wanted = RecoveryPositionType(dir);
      bool chooseSmallest = excessUnits < minUnits;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol ||
            PositionGetInteger(POSITION_MAGIC) != (long)RecoveryMagic_ ||
            PositionGetInteger(POSITION_TYPE) != wanted)
            continue;
         long units = VolumeStepUnits(PositionGetDouble(POSITION_VOLUME));
         if(units <= 0) continue;
         if(ticketOut == 0 ||
            (chooseSmallest && (units < ticketUnitsOut ||
             (units == ticketUnitsOut && ticket < ticketOut))) ||
            (!chooseSmallest && (units > ticketUnitsOut ||
             (units == ticketUnitsOut && ticket < ticketOut))))
         {
            ticketOut = ticket;
            ticketUnitsOut = units;
         }
      }
      return ticketOut != 0;
   }

   bool SpecificTicketLive(const int idx,
                           ulong &ticketOut,
                           long &ownerMagicOut) const
   {
      ticketOut = 0;
      ownerMagicOut = 0;
      ulong tickets[2];
      tickets[0] = m_cycle[idx].ticketFirst;
      tickets[1] = m_cycle[idx].ticketSecond;
      int count = m_cycle[idx].ticketCount;
      for(int i = 0; i < count && i < 2; i++)
      {
         ulong ticket = tickets[i];
         if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         long magic = PositionGetInteger(POSITION_MAGIC);
         if(!IsLegacyManagedMagic(magic)) continue;
         if(PositionGetInteger(POSITION_TYPE) != CorePositionType(Direction(idx))) continue;
         ticketOut = ticket;
         ownerMagicOut = magic;
         return true;
      }
      return false;
   }

   long CoreMagicUnitsForTicket(const eRecoveryCoreDirection dir,
                                const ulong ticket) const
   {
      if(ticket == 0 || !PositionSelectByTicket(ticket)) return 0;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol ||
         PositionGetInteger(POSITION_MAGIC) != (long)Magic ||
         PositionGetInteger(POSITION_TYPE) != CorePositionType(dir))
         return 0;
      return VolumeStepUnits(PositionGetDouble(POSITION_VOLUME));
   }

   bool CycleRequiresCoordination(const eRecoveryCoreDirection dir) const
   {
      if(RecoveryMode_ != recovery_ACTIVE || m_recovery == NULL || m_exec == NULL)
         return false;
      SRecoveryCycle cycle;
      m_recovery.GetCycle(dir, cycle);
      if(Recovery_ExitStateNeedsCoordination(cycle.state)) return true;
      if(RecoveryUnits(dir) > 0) return true;
      return m_exec.HasPendingForCycle(Recovery_CycleKey(dir));
   }

   // Closing DEAL_MAGIC may be 0 for a manual/mobile/web close even when the
   // position being closed was opened by Core/Recovery. Resolve the original
   // owner from DEAL_POSITION_ID before classifying intervention.
   long ResolveClosedOwnerMagic(const ulong closingDeal) const
   {
      if(closingDeal == 0 || !HistoryDealSelect(closingDeal)) return 0;
      long direct = HistoryDealGetInteger(closingDeal, DEAL_MAGIC);
      if(direct == (long)Magic || direct == (long)RecoveryMagic_) return direct;

      ulong positionId = (ulong)HistoryDealGetInteger(closingDeal, DEAL_POSITION_ID);
      if(positionId == 0 || !HistorySelectByPosition(positionId)) return direct;

      long owner = direct;
      datetime ownerTime = 0;
      for(int i = 0; i < HistoryDealsTotal(); i++)
      {
         ulong deal = HistoryDealGetTicket(i);
         if(deal == 0) continue;
         if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol) continue;
         long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
         if(entry != DEAL_ENTRY_IN && entry != DEAL_ENTRY_INOUT) continue;
         datetime t = (datetime)HistoryDealGetInteger(deal, DEAL_TIME);
         if(ownerTime == 0 || t < ownerTime)
         {
            owner = HistoryDealGetInteger(deal, DEAL_MAGIC);
            ownerTime = t;
         }
      }
      return owner;
   }

   bool IsExpectedRecoveryLockSl(const eRecoveryCoreDirection dir,
                                 const ulong closingDeal) const
   {
      if(m_recovery == NULL || closingDeal == 0 || !HistoryDealSelect(closingDeal))
         return false;
      SRecoveryCycle cycle;
      m_recovery.GetCycle(dir, cycle);
      double targetSl = m_recovery.LockTargetPrice(dir);
      double dealPrice = HistoryDealGetDouble(closingDeal, DEAL_PRICE);
      long reason = HistoryDealGetInteger(closingDeal, DEAL_REASON);
      double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double spreadPrice = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point;
      if(tickSize <= 0.0) return false;

      // Protective stops can fill a few ticks/spread away from the requested
      // SL. Keep the acceptance window bounded and require the locked-state +
      // owner/reason evidence as well; anything outside this remains fail-closed.
      double tolerance = MathMax(25.0 * tickSize,
                                 2.0 * spreadPrice + 2.0 * tickSize);
      return Recovery_ExitExpectedLockSlPure(cycle.state, reason, dealPrice,
                                             targetSl, tolerance);
   }

   void LatchExternal(const eRecoveryCoreDirection dir,
                      const eRecoveryExitCoordReason reason,
                      const datetime now)
   {
      int idx = Index(dir);
      m_cycle[idx].active          = true;
      m_cycle[idx].reconcileHold   = false;
      m_cycle[idx].kind            = recovery_EXIT_COORD_EXTERNAL;
      m_cycle[idx].reason          = reason;
      m_cycle[idx].targetCoreUnits = 0;
      m_cycle[idx].ticketFirst     = 0;
      m_cycle[idx].ticketSecond    = 0;
      m_cycle[idx].ticketCount     = 0;
      m_cycle[idx].startedAt       = now;
   }

   bool SubmitRecoveryTrim(const int idx,
                           const long excessUnits,
                           string &why)
   {
      eRecoveryCoreDirection dir = Direction(idx);
      double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      double minVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      long minUnits = Recovery_VolumeToUnitsCeil(minVol, step);
      if(step <= 0.0 || minUnits <= 0)
      {
         why = "invalid volume metadata during exit cleanup";
         m_cycle[idx].active = false;
         m_cycle[idx].reconcileHold = true;
         return false;
      }

      ulong ticket = 0;
      long ticketUnits = 0;
      if(!SelectRecoveryTrimTicket(dir, excessUnits, minUnits, ticket, ticketUnits))
      {
         why = "Recovery hedge exposure exists but no matching child ticket is selectable";
         m_cycle[idx].active = false;
         m_cycle[idx].reconcileHold = true;
         return false;
      }

      long requestUnits = Recovery_ExitTrimRequestUnits(excessUnits, ticketUnits, minUnits);
      if(requestUnits <= 0)
      {
         why = "Recovery cleanup trim target is not executable";
         m_cycle[idx].active = false;
         m_cycle[idx].reconcileHold = true;
         return false;
      }

      double volume = Recovery_UnitsToVolume(requestUnits, step);
      int cycleKey = Recovery_CycleKey(dir);
      bool durable = m_recovery != NULL && m_recovery.ActiveReady();
      if(durable && !m_recovery.ArmDurableCommand(dir, EXEC_CMD_RECOVERY_CLOSE,
                                                   (long)RecoveryMagic_, ticket,
                                                   requestUnits, RecoveryUnits(dir),
                                                   0.0, 0, 0, why))
         return false;
      bool sent = m_exec.ClosePositionVolumeOwned(ticket, volume,
                                                  (long)RecoveryMagic_, cycleKey,
                                                  EXEC_CMD_RECOVERY_CLOSE,
                                                  EXEC_RECONCILE_FAIL_CLOSED);
      if(!sent)
      {
         if(durable && !m_exec.HasReconcileRequired(cycleKey))
            m_recovery.CancelDurableCommand(dir);
         why = m_exec.HasReconcileRequired(cycleKey) ?
               "Recovery cleanup hedge close is ambiguous; reconciliation required" :
               "Recovery cleanup hedge close request was rejected";
         m_cycle[idx].active = false;
         m_cycle[idx].reconcileHold = true;
      }
      return sent;
   }

   bool SubmitManagedCoreClose(const int idx,
                               const ulong ticket,
                               const long ownerMagic,
                               string &why)
   {
      if(ticket == 0 || !PositionSelectByTicket(ticket)) return false;
      double volume = PositionGetDouble(POSITION_VOLUME);
      if(volume <= 0.0) return false;
      if(ownerMagic == (long)Magic)
      {
         eRecoveryCoreDirection dir = Direction(idx);
         int cycleKey = Recovery_CycleKey(dir);
         long units = VolumeStepUnits(volume);
         bool durable = m_recovery != NULL && m_recovery.ActiveReady();
         if(durable && !m_recovery.ArmDurableCommand(dir, EXEC_CMD_RECOVERY_CLOSE,
                                                      (long)Magic, ticket, units,
                                                      CoreMagicUnits(dir), 0.0,
                                                      0, 0, why))
            return false;
         bool sent = m_exec.ClosePositionVolumeOwned(ticket, volume,
                                                     (long)Magic, cycleKey,
                                                     EXEC_CMD_RECOVERY_CLOSE,
                                                     EXEC_RECONCILE_FAIL_CLOSED);
         if(!sent)
         {
            if(durable && !m_exec.HasReconcileRequired(cycleKey))
               m_recovery.CancelDurableCommand(dir);
            why = m_exec.HasReconcileRequired(cycleKey) ?
                  "coordinated Core close is ambiguous; reconciliation required" :
                  "coordinated Core close request was rejected";
            m_cycle[idx].active = false;
            m_cycle[idx].reconcileHold = true;
         }
         return sent;
      }

      // Legacy BasketManager may manage magic-0 positions when flag_Hand_Ord.
      // Close them with the legacy owner-preserving path, but keep the side
      // cleanup latched until the ticket is broker-observably gone.
      bool sent = m_exec.ClosePosition(ticket);
      if(sent) m_cycle[idx].legacyPendingTicket = ticket;
      else
      {
         why = "legacy-managed manual ticket close failed during coordinated exit";
         m_cycle[idx].active = false;
         m_cycle[idx].reconcileHold = true;
      }
      return sent;
   }

   bool LegacyTicketStillPending(const int idx)
   {
      ulong ticket = m_cycle[idx].legacyPendingTicket;
      if(ticket == 0) return false;
      if(m_exec.HasPendingClose(ticket)) return true;
      if(!PositionSelectByTicket(ticket))
      {
         m_cycle[idx].legacyPendingTicket = 0;
         return false;
      }
      m_cycle[idx].legacyPendingTicket = 0;
      return false;
   }

   bool DriveCycle(const int idx, const datetime now, string &why)
   {
      if(m_cycle[idx].reconcileHold && !m_cycle[idx].active)
      {
         if(m_cycle[idx].kind == recovery_EXIT_COORD_EXTERNAL)
         {
            why = "external Core/Recovery mutation remains fail-closed pending explicit reconciliation";
            return true;
         }
         string finalizeWhy = "";
         if(m_recovery != NULL &&
            m_recovery.FinalizeConfirmedSideMutation(*m_exec, Direction(idx), now, finalizeWhy))
         {
            Log_Info("Recovery", "T13 deferred side-mutation finalization succeeded for " +
                     Recovery_DirectionName(Direction(idx)));
            ResetCycle(idx);
            return false;
         }
         why = "T13 side-mutation finalizer still blocked: " + finalizeWhy;
         return true;
      }
      if(!m_cycle[idx].active) return false;
      if(LegacyTicketStillPending(idx)) return true;

      eRecoveryCoreDirection dir = Direction(idx);
      int cycleKey = Recovery_CycleKey(dir);
      if(m_recovery != NULL && m_recovery.ActiveReady() && m_recovery.HasDurableCommand(dir))
      {
         string durableWhy = "";
         if(!m_recovery.ResolveDurableCommand(*m_exec, dir, now, durableWhy))
         {
            m_cycle[idx].active = false;
            m_cycle[idx].reconcileHold = true;
            why = durableWhy;
            return true;
         }
      }
      m_exec.ReconcileCycle(cycleKey);
      if(m_exec.HasReconcileRequired(cycleKey))
      {
         m_cycle[idx].active = false;
         m_cycle[idx].reconcileHold = true;
         why = "Recovery execution journal requires reconciliation during exit cleanup";
         return true;
      }
      if(m_exec.HasPendingForCycle(cycleKey)) return true;

      long currentCoreUnits = CoreMagicUnits(dir);
      long activeHedgeUnits = RecoveryUnits(dir);
      bool managedLive = false;
      ulong selectedTicket = 0;
      long selectedOwner = 0;

      if(m_cycle[idx].kind == recovery_EXIT_COORD_TICKETS)
         managedLive = SpecificTicketLive(idx, selectedTicket, selectedOwner);
      else if(m_cycle[idx].kind == recovery_EXIT_COORD_FULL_SIDE)
         managedLive = SelectOldestManagedSideTicket(dir, selectedTicket, selectedOwner);

      eRecoveryExitCoordStep step = Recovery_ExitNextStepPure(
         m_cycle[idx].kind == recovery_EXIT_COORD_EXTERNAL,
         currentCoreUnits,
         m_cycle[idx].targetCoreUnits,
         activeHedgeUnits,
         managedLive);

      if(step == recovery_EXIT_STEP_TRIM_HEDGE)
      {
         long excess = Recovery_ExitExcessHedgeUnits(currentCoreUnits,
                                                      m_cycle[idx].targetCoreUnits,
                                                      activeHedgeUnits,
                                                      m_cycle[idx].kind == recovery_EXIT_COORD_EXTERNAL);
         SubmitRecoveryTrim(idx, excess, why);
         return true;
      }

      if(step == recovery_EXIT_STEP_CLOSE_CORE)
      {
         if(!managedLive || selectedTicket == 0)
         {
            m_cycle[idx].active = false;
            m_cycle[idx].reconcileHold = true;
            why = m_cycle[idx].kind == recovery_EXIT_COORD_TICKETS ?
                  "specific legacy exit tickets disappeared before planned target was reached" :
                  "full-side exit target not reached but no legacy-managed ticket is selectable";
            return true;
         }
         SubmitManagedCoreClose(idx, selectedTicket, selectedOwner, why);
         return true;
      }

      if(step == recovery_EXIT_STEP_RECONCILE_HOLD)
      {
         m_cycle[idx].active = false;
         if(currentCoreUnits <= 0 && activeHedgeUnits <= 0 &&
            m_cycle[idx].kind == recovery_EXIT_COORD_EXTERNAL)
         {
            string finalizeWhy = "";
            if(m_recovery.FinalizeConfirmedSideMutation(*m_exec, dir, now, finalizeWhy))
            {
               Log_Info("Recovery", "T13 externally-flattened " + Recovery_DirectionName(dir) +
                        " terminalized safely");
               ResetCycle(idx);
               return false;
            }
            why = "T13 external flat finalizer blocked: " + finalizeWhy;
         }
         // Partial/unknown external changes remain fail-closed.
         m_cycle[idx].reconcileHold = true;
         return true;
      }

      if(step == recovery_EXIT_STEP_COMPLETE)
      {
         // T13 replaces the old permanent partial reconcileHold with an
         // explicit side-scoped broker reconciliation + durable save. This
         // handles both full-side/magic closes and stable-state Overlap.
         string finalizeWhy = "";
         if(!m_recovery.FinalizeConfirmedSideMutation(*m_exec, dir, now, finalizeWhy))
         {
            m_cycle[idx].active = false;
            m_cycle[idx].reconcileHold = true;
            why = "T13 side-mutation finalizer blocked: " + finalizeWhy;
            return true;
         }
         Log_Info("Recovery", "T13 coordinated Core mutation complete for " +
                  Recovery_DirectionName(dir) + " — Recovery state persisted");
         ResetCycle(idx);
         return false;
      }
      return false;
   }

public:
   CRecoveryExitCoordinator(void)
   {
      m_recovery = NULL;
      m_exec = NULL;
      m_accountWidePending = false;
      m_accountWideStartedAt = 0;
      ResetCycle(0);
      ResetCycle(1);
   }

   void Init(CRecoveryEngine *recovery, CExecutionLayer *exec)
   {
      m_recovery = recovery;
      m_exec = exec;
      m_accountWidePending = false;
      m_accountWideStartedAt = 0;
      Recovery_ClearGlobalFlattenFinalization();
      ResetCycle(0);
      ResetCycle(1);
   }

   bool HasBlockingWork() const
   {
      if(RecoveryMode_ != recovery_ACTIVE) return false;
      if(m_accountWidePending) return true;
      for(int i = 0; i < 2; i++)
         if(m_cycle[i].active || m_cycle[i].reconcileHold) return true;
      return false;
   }

   bool ReconcileHold(const eRecoveryCoreDirection dir) const
   {
      return m_cycle[Index(dir)].reconcileHold;
   }

   eRecoveryOverlapPolicy OverlapCapabilityPolicy(
      const eRecoveryCoreDirection dir) const
   {
      if(RecoveryMode_ != recovery_ACTIVE || m_recovery == NULL || m_exec == NULL)
         return recovery_OVERLAP_BYPASS;

      SRecoveryCycle cycle;
      m_recovery.GetCycle(dir, cycle);
      int idx = Index(dir);
      bool coordinatorPending = m_accountWidePending ||
                                m_cycle[idx].active ||
                                m_cycle[idx].reconcileHold;
      return Recovery_OverlapCapabilityPolicyPure(
         cycle.state,
         m_recovery.ActiveReady(),
         m_recovery.HasDurableCommand(dir),
         m_exec.HasPendingMutation(),
         coordinatorPending);
   }

   void ClearReconcileHold(const eRecoveryCoreDirection dir)
   {
      int idx = Index(dir);
      if(m_cycle[idx].active) return;
      m_cycle[idx].reconcileHold = false;
   }

   eRecoveryExitCoordRequest BeginFullSideClose(const eRecoveryCoreDirection dir,
                                                const eRecoveryExitCoordReason reason,
                                                const datetime now)
   {
      if(RecoveryMode_ != recovery_ACTIVE || m_recovery == NULL || m_exec == NULL)
         return recovery_EXIT_BYPASS;
      int idx = Index(dir);
      if(!CycleRequiresCoordination(dir) && !m_cycle[idx].reconcileHold)
         return recovery_EXIT_BYPASS;

      // Full-side risk reduction is stronger than an earlier partial intent.
      m_cycle[idx].active          = true;
      m_cycle[idx].reconcileHold   = false;
      m_cycle[idx].kind            = recovery_EXIT_COORD_FULL_SIDE;
      m_cycle[idx].reason          = reason;
      m_cycle[idx].targetCoreUnits = 0;
      m_cycle[idx].ticketFirst     = 0;
      m_cycle[idx].ticketSecond    = 0;
      m_cycle[idx].ticketCount     = 0;
      m_cycle[idx].startedAt       = now;
      return recovery_EXIT_LATCHED;
   }

   eRecoveryExitCoordRequest BeginTicketClose(const eRecoveryCoreDirection dir,
                                              const ulong firstTicket,
                                              const ulong secondTicket,
                                              const eRecoveryExitCoordReason reason,
                                              const datetime now)
   {
      if(RecoveryMode_ != recovery_ACTIVE || m_recovery == NULL || m_exec == NULL)
         return recovery_EXIT_BYPASS;
      int idx = Index(dir);
      if(m_cycle[idx].reconcileHold) return recovery_EXIT_BLOCKED;
      if(m_cycle[idx].active) return recovery_EXIT_LATCHED;

      // T13: Overlap is a non-emergency topology mutation. Let it bypass only
      // before Recovery owns the cycle, coordinate it in stable Recovery
      // states, and DEFER while T4/T5/T6 is mutating/pausing/reconciling.
      if(reason == recovery_EXIT_REASON_LEGACY_OVERLAP)
      {
         eRecoveryOverlapPolicy p = OverlapCapabilityPolicy(dir);
         if(p == recovery_OVERLAP_BYPASS) return recovery_EXIT_BYPASS;
         if(p == recovery_OVERLAP_DEFER)
            return recovery_EXIT_BLOCKED;
      }
      else if(!CycleRequiresCoordination(dir))
         return recovery_EXIT_BYPASS;

      if(firstTicket == 0 && secondTicket == 0) return recovery_EXIT_BLOCKED;
      long currentCore = CoreMagicUnits(dir);
      long intendedCoreClose = CoreMagicUnitsForTicket(dir, firstTicket);
      if(secondTicket != 0 && secondTicket != firstTicket)
         intendedCoreClose += CoreMagicUnitsForTicket(dir, secondTicket);

      m_cycle[idx].active          = true;
      m_cycle[idx].kind            = recovery_EXIT_COORD_TICKETS;
      m_cycle[idx].reason          = reason;
      m_cycle[idx].targetCoreUnits = Recovery_ExitPostCoreUnits(currentCore,
                                                                 intendedCoreClose);
      m_cycle[idx].ticketFirst     = firstTicket;
      m_cycle[idx].ticketSecond    = secondTicket;
      m_cycle[idx].ticketCount     = secondTicket != 0 && secondTicket != firstTicket ? 2 : 1;
      m_cycle[idx].startedAt       = now;
      return recovery_EXIT_LATCHED;
   }

   void BeginAccountWideClose(const datetime now)
   {
      if(RecoveryMode_ != recovery_ACTIVE || m_exec == NULL) return;
      if(m_accountWidePending) return;
      m_accountWidePending = true;
      m_accountWideStartedAt = now;
      Recovery_ClearGlobalFlattenFinalization();
      // Account/global emergency preempts both narrower cycle coordinators.
      ResetCycle(0);
      ResetCycle(1);
   }

   bool Drive(const datetime now, string &why)
   {
      why = "";
      if(RecoveryMode_ != recovery_ACTIVE || m_recovery == NULL || m_exec == NULL)
         return false;

      if(m_accountWidePending)
      {
         // Do not duplicate an in-flight close. A pre-existing OPEN/MODIFY can
         // also resolve after the account is momentarily flat, so the global
         // latch is not released until the ENTIRE execution journal is quiet.
         if(m_exec.HasAnyPendingClose()) return true;
         if(PositionsTotal() > 0)
         {
            int sent = m_exec.CloseAllAccount();
            if(sent <= 0)
               why = "account-wide close still has positions but no close request was accepted";
            return true;
         }
         if(!Recovery_GlobalFlattenReadyPure(PositionsTotal(), m_exec.HasPending()))
         {
            why = "account-wide close is flat but execution journal still has unresolved request(s)";
            return true;
         }

         string finalizeWhy = "";
         if(!m_recovery.FinalizeConfirmedGlobalFlatten(*m_exec, now, finalizeWhy))
         {
            why = "T12 global flatten finalizer blocked: " + finalizeWhy;
            return true;
         }

         Recovery_ClearGlobalFlattenFinalization();
         m_accountWidePending = false;
         m_accountWideStartedAt = 0;
         ResetCycle(0);
         ResetCycle(1);
         Log_Info("Recovery",
                  "GLOBAL FLATTEN complete — atomic Recovery state persisted; ACTIVE re-armed; new Core series enabled");
         return false;
      }

      bool blocking = false;
      string w0 = "", w1 = "";
      if(DriveCycle(0, now, w0)) blocking = true;
      if(DriveCycle(1, now, w1)) blocking = true;
      if(w0 != "") why = w0;
      if(w1 != "") why = why == "" ? w1 : why + "; " + w1;
      return blocking || HasBlockingWork();
   }

   // Return true when this close deal belongs to T8 cleanup/reconcile and must
   // not be consumed as normal T5 hedge-credit/Core-debit evidence.
   bool OnTradeTransaction(const MqlTradeTransaction &trans)
   {
      if(RecoveryMode_ != recovery_ACTIVE || m_recovery == NULL || m_exec == NULL)
         return false;
      if(trans.type != TRADE_TRANSACTION_DEAL_ADD || trans.deal == 0 ||
         trans.symbol != _Symbol || !HistoryDealSelect(trans.deal))
         return false;
      long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY) return false;

      long ownerMagic = ResolveClosedOwnerMagic(trans.deal);
      if(ownerMagic != (long)Magic && ownerMagic != (long)RecoveryMagic_) return false;

      // ResolveClosedOwnerMagic may have changed the selected history range;
      // reselect the actual closing deal before reading its type/reason/time.
      if(!HistoryDealSelect(trans.deal)) return false;
      long type = HistoryDealGetInteger(trans.deal, DEAL_TYPE);
      long reason = HistoryDealGetInteger(trans.deal, DEAL_REASON);

      eRecoveryCoreDirection dir = recovery_CORE_BUY;
      bool mapped = true;
      if(ownerMagic == (long)Magic)
      {
         if(type == DEAL_TYPE_SELL) dir = recovery_CORE_BUY;
         else if(type == DEAL_TYPE_BUY) dir = recovery_CORE_SELL;
         else mapped = false;
      }
      else
      {
         if(type == DEAL_TYPE_BUY) dir = recovery_CORE_BUY;       // closes SELL hedge
         else if(type == DEAL_TYPE_SELL) dir = recovery_CORE_SELL;// closes BUY hedge
         else mapped = false;
      }
      if(!mapped) return false;

      int idx = Index(dir);
      bool coordinatorOwned = m_accountWidePending || m_cycle[idx].active;

      // A T6 protective lock is submitted by the EA but its eventual fill is
      // reported by MT5 as DEAL_REASON_SL, not DEAL_REASON_EXPERT. When the
      // owner/state/target-price evidence matches, this is an expected internal
      // lifecycle event and must not latch an external reconciliation hold.
      if(!coordinatorOwned && ownerMagic == (long)RecoveryMagic_ &&
         IsExpectedRecoveryLockSl(dir, trans.deal))
      {
         Log_Info("Recovery", "locksl" + (string)Recovery_CycleKey(dir),
                  "expected Recovery protective SL executed for " +
                  Recovery_DirectionName(dir) + " — external latch skipped");
         return false;
      }

      if(Recovery_ExitExternalDealReason(reason))
      {
         if(!m_accountWidePending)
            LatchExternal(dir,
                          ownerMagic == (long)Magic ? recovery_EXIT_REASON_EXTERNAL_CORE :
                                                     recovery_EXIT_REASON_EXTERNAL_RECOVERY,
                          (datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME));
         Log_Warn("Recovery", "external" + (string)Recovery_CycleKey(dir),
                  "external/broker close detected for " + Recovery_DirectionName(dir) +
                  " originalOwner=" + (string)ownerMagic +
                  " reason=" + (string)reason +
                  " — cleanup/reconciliation latched");
         return true;
      }

      return coordinatorOwned;
   }
};

#endif // BD_RECOVERY_EXIT_COORDINATOR_MQH
