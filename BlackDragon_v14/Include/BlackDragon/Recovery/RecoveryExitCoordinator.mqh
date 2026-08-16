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
   recovery_EXIT_REASON_PANEL,
   recovery_EXIT_REASON_LEGACY_TP,
   recovery_EXIT_REASON_LEGACY_SL,
   recovery_EXIT_REASON_LEGACY_TRAIL,
   recovery_EXIT_REASON_LEGACY_OVERLAP,
   recovery_EXIT_REASON_GUARD_SIDE,
   recovery_EXIT_REASON_GUARD_MAGIC,
   recovery_EXIT_REASON_GUARD_DAILY,
   recovery_EXIT_REASON_EXTERNAL_CORE,
   recovery_EXIT_REASON_EXTERNAL_RECOVERY
};

enum eRecoveryExitCoordRequest
{
   recovery_EXIT_BYPASS = 0,   // legacy path is safe and remains authoritative
   recovery_EXIT_LATCHED,      // coordinator owns this exit until safe completion
   recovery_EXIT_BLOCKED       // fail closed; do not fall back to legacy mutation
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

// CORE_ONLY has no Recovery mutation/exposure contract yet; ARMED has only a
// latch/anchor. Any later state may own a hedge or unresolved command and must
// therefore be coordinated before legacy Core exposure is reduced.
bool Recovery_ExitStateNeedsCoordination(const eRecoveryState state)
{
   return state != recovery_CORE_ONLY &&
          state != recovery_ARMED &&
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

// Cleanup never opens/top-ups a hedge. If the exact excess is below broker
// minimum, closing one complete child is allowed: under-coverage is safer than
// knowingly retaining a naked/over-hedged residual during an exit sequence.
long Recovery_ExitTrimRequestUnits(const long excessUnits,
                                   const long selectedTicketUnits,
                                   const long minUnits)
{
   if(excessUnits <= 0 || selectedTicketUnits <= 0 || minUnits <= 0) return 0;
   if(excessUnits < minUnits) return selectedTicketUnits;
   return excessUnits < selectedTicketUnits ? excessUnits : selectedTicketUnits;
}

bool Recovery_ExitExternalDealReason(const long dealReason)
{
   return dealReason != DEAL_REASON_EXPERT;
}

eRecoveryExitCoordStep Recovery_ExitNextStepPure(const bool externalMutation,
                                                 const long currentCoreUnits,
                                                 const long targetCoreUnits,
                                                 const long activeHedgeUnits,
                                                 const bool intendedCoreTicketLive)
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

   if(intendedCoreTicketLive || currentCoreUnits > targetCoreUnits)
      return recovery_EXIT_STEP_CLOSE_CORE;

   if(activeHedgeUnits > currentCoreUnits)
      return recovery_EXIT_STEP_TRIM_HEDGE;
   return recovery_EXIT_STEP_COMPLETE;
}

class CRecoveryExitCoordinator
{
private:
   CRecoveryEngine       *m_recovery;
   CExecutionLayer       *m_exec;
   SRecoveryExitCoordCycle m_cycle[2];
   bool                   m_accountWidePending;
   datetime               m_accountWideStartedAt;

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
      const SRecoveryExitCoordCycle &c = m_cycle[idx];
      ulong tickets[2];
      tickets[0] = c.ticketFirst;
      tickets[1] = c.ticketSecond;
      for(int i = 0; i < c.ticketCount && i < 2; i++)
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
      bool sent = m_exec.ClosePositionVolumeOwned(ticket, volume,
                                                  (long)RecoveryMagic_, cycleKey,
                                                  EXEC_CMD_RECOVERY_CLOSE,
                                                  EXEC_RECONCILE_FAIL_CLOSED);
      if(!sent)
      {
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
         int cycleKey = Recovery_CycleKey(Direction(idx));
         bool sent = m_exec.ClosePositionVolumeOwned(ticket, volume,
                                                     (long)Magic, cycleKey,
                                                     EXEC_CMD_RECOVERY_CLOSE,
                                                     EXEC_RECONCILE_FAIL_CLOSED);
         if(!sent)
         {
            why = m_exec.HasReconcileRequired(cycleKey) ?
                  "coordinated Core close is ambiguous; reconciliation required" :
                  "coordinated Core close request was rejected";
            m_cycle[idx].active = false;
            m_cycle[idx].reconcileHold = true;
         }
         return sent;
      }

      // Preserve legacy flag_Hand_Ord semantics. Manual magic-0 tickets are
      // part of the legacy basket but not part of Recovery ownership/coverage.
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
      // Journal resolved/released but ticket still exists: allow deterministic
      // retry through the normal selection path rather than assuming success.
      m_cycle[idx].legacyPendingTicket = 0;
      return false;
   }

   bool DriveCycle(const int idx, const datetime now, string &why)
   {
      SRecoveryExitCoordCycle &c = m_cycle[idx];
      if(c.reconcileHold && !c.active) return true;
      if(!c.active) return false;
      if(LegacyTicketStillPending(idx)) return true;

      eRecoveryCoreDirection dir = Direction(idx);
      int cycleKey = Recovery_CycleKey(dir);
      m_exec.ReconcileCycle(cycleKey);
      if(m_exec.HasReconcileRequired(cycleKey))
      {
         c.active = false;
         c.reconcileHold = true;
         why = "Recovery execution journal requires reconciliation during exit cleanup";
         return true;
      }
      if(m_exec.HasPendingForCycle(cycleKey)) return true;

      long currentCoreUnits = CoreMagicUnits(dir);
      long activeHedgeUnits = RecoveryUnits(dir);
      bool specificLive = false;
      ulong selectedTicket = 0;
      long selectedOwner = 0;
      if(c.kind == recovery_EXIT_COORD_TICKETS)
         specificLive = SpecificTicketLive(idx, selectedTicket, selectedOwner);

      eRecoveryExitCoordStep step = Recovery_ExitNextStepPure(
         c.kind == recovery_EXIT_COORD_EXTERNAL,
         currentCoreUnits,
         c.targetCoreUnits,
         activeHedgeUnits,
         specificLive);

      if(step == recovery_EXIT_STEP_TRIM_HEDGE)
      {
         long excess = Recovery_ExitExcessHedgeUnits(currentCoreUnits,
                                                      c.targetCoreUnits,
                                                      activeHedgeUnits,
                                                      c.kind == recovery_EXIT_COORD_EXTERNAL);
         SubmitRecoveryTrim(idx, excess, why);
         return true;
      }

      if(step == recovery_EXIT_STEP_CLOSE_CORE)
      {
         if(c.kind == recovery_EXIT_COORD_TICKETS)
         {
            if(!specificLive)
            {
               c.active = false;
               c.reconcileHold = true;
               why = "specific legacy exit tickets disappeared but Core exposure did not reach planned target";
               return true;
            }
            SubmitManagedCoreClose(idx, selectedTicket, selectedOwner, why);
            return true;
         }

         ulong ticket = 0;
         long ownerMagic = 0;
         if(!SelectOldestManagedSideTicket(dir, ticket, ownerMagic))
         {
            c.active = false;
            c.reconcileHold = true;
            why = "full-side exit target not reached but no legacy-managed Core ticket is selectable";
            return true;
         }
         SubmitManagedCoreClose(idx, ticket, ownerMagic, why);
         return true;
      }

      if(step == recovery_EXIT_STEP_RECONCILE_HOLD)
      {
         // External Core/Recovery mutation was made outside the coordinator.
         // Once over-hedge risk is removed, freeze normal Recovery/DCA work
         // until T9 broker/history reconciliation proves a safe continuation.
         c.active = false;
         SRecoveryCycle cycle;
         m_recovery.GetCycle(dir, cycle);
         if(currentCoreUnits <= 0 && activeHedgeUnits <= 0)
            c.reconcileHold = false;
         else if(cycle.state == recovery_CORE_ONLY && activeHedgeUnits <= 0 &&
                 !m_exec.HasPendingForCycle(cycleKey))
            c.reconcileHold = false; // no Recovery state/exposure was involved
         else
            c.reconcileHold = true;
         return c.reconcileHold;
      }

      if(step == recovery_EXIT_STEP_COMPLETE)
      {
         c.active = false;
         // Partial deterministic exits (Overlap) leave a Core series alive.
         // Keep a fail-closed reconcile hold until T9 refreshes the Recovery
         // registry from broker/history. Full-side cleanup is exposure-flat.
         c.reconcileHold = (c.kind == recovery_EXIT_COORD_TICKETS &&
                            (currentCoreUnits > 0 || activeHedgeUnits > 0));
         return c.reconcileHold;
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

      // A full risk-reducing exit may override a previous reconcile hold or a
      // narrower partial intent; it never falls back to unsafe legacy mutation.
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
      if(!CycleRequiresCoordination(dir)) return recovery_EXIT_BYPASS;
      if(firstTicket == 0 && secondTicket == 0) return recovery_EXIT_BLOCKED;

      if(m_cycle[idx].active)
      {
         // A previously latched full-side exit is stronger; do not downgrade it.
         return recovery_EXIT_LATCHED;
      }

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
      m_accountWidePending = true;
      m_accountWideStartedAt = now;
      // Account/global emergency preempts narrower per-cycle cleanup.
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
         if(m_exec.HasAnyPendingClose()) return true;
         if(PositionsTotal() > 0)
         {
            int sent = m_exec.CloseAllAccount();
            if(sent <= 0) why = "account-wide close still has positions but no close request was accepted";
            return true;
         }
         m_accountWidePending = false;
         m_accountWideStartedAt = 0;
         ResetCycle(0);
         ResetCycle(1);
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

   // Returns true when RecoveryEngine must NOT consume this closing deal as
   // normal T5 realized-credit evidence. Coordinator-owned closes and any
   // non-EXPERT Core/Recovery close are cleanup/reconcile evidence instead.
   bool OnTradeTransaction(const MqlTradeTransaction &trans)
   {
      if(RecoveryMode_ != recovery_ACTIVE || m_recovery == NULL || m_exec == NULL)
         return false;
      if(trans.type != TRADE_TRANSACTION_DEAL_ADD || trans.deal == 0 ||
         trans.symbol != _Symbol || !HistoryDealSelect(trans.deal))
         return false;
      long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY) return false;

      long magic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
      if(magic != (long)Magic && magic != (long)RecoveryMagic_) return false;
      long type = HistoryDealGetInteger(trans.deal, DEAL_TYPE);
      long reason = HistoryDealGetInteger(trans.deal, DEAL_REASON);

      eRecoveryCoreDirection dir;
      bool mapped = true;
      if(magic == (long)Magic)
      {
         if(type == DEAL_TYPE_SELL) dir = recovery_CORE_BUY;
         else if(type == DEAL_TYPE_BUY) dir = recovery_CORE_SELL;
         else mapped = false;
      }
      else
      {
         if(type == DEAL_TYPE_BUY) dir = recovery_CORE_BUY;   // closes SELL Recovery hedge
         else if(type == DEAL_TYPE_SELL) dir = recovery_CORE_SELL; // closes BUY Recovery hedge
         else mapped = false;
      }
      if(!mapped) return false;

      int idx = Index(dir);
      bool coordinatorOwned = m_accountWidePending || m_cycle[idx].active;
      if(Recovery_ExitExternalDealReason(reason))
      {
         if(!m_accountWidePending)
            LatchExternal(dir,
                          magic == (long)Magic ? recovery_EXIT_REASON_EXTERNAL_CORE :
                                                recovery_EXIT_REASON_EXTERNAL_RECOVERY,
                          (datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME));
         Log_Warn("Recovery", "external" + (string)Recovery_CycleKey(dir),
                  "external/broker Core-Recovery close detected for " +
                  Recovery_DirectionName(dir) + " reason=" + (string)reason +
                  " — cleanup/reconciliation latched");
         return true;
      }

      return coordinatorOwned;
   }
};

#endif // BD_RECOVERY_EXIT_COORDINATOR_MQH
