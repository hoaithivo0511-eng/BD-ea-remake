//+------------------------------------------------------------------+
//| RecoveryExitCoordinator.mqh — T16.2 ARCS exit/mutation wrapper   |
//| T13 remains pinned. T16 owns stacked overlap topology explicitly.|
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_EXIT_COORDINATOR_T16_WRAPPER_MQH
#define BD_RECOVERY_EXIT_COORDINATOR_T16_WRAPPER_MQH

#include "RecoveryEngine.mqh"
#include "RecoveryGlobalFlatten.mqh"
#include "RecoveryMutationPolicy.mqh"
#include "RecoveryExecutionIdentity.mqh"
#include <BlackDragon/BasketManager.mqh>

#define private protected
#define CRecoveryExitCoordinator CRecoveryExitCoordinatorT13Base
#include "RecoveryExitCoordinatorT13Base.mqh"
#undef CRecoveryExitCoordinator
#undef private

class CRecoveryExitCoordinator : public CRecoveryExitCoordinatorT13Base
{
private:
   bool IsT16Arcs() const
   {
      return RecoveryMode_ == recovery_ACTIVE && Recovery_T16UseStackEngine();
   }

   bool IsT16OverlapCycle(const int idx) const
   {
      return IsT16Arcs() && OverlapAfterHedge_ &&
             m_cycle[idx].reason == recovery_EXIT_REASON_LEGACY_OVERLAP &&
             (m_cycle[idx].active || m_cycle[idx].reconcileHold);
   }

   bool IsExpectedRecoveryLockSlT14(const eRecoveryCoreDirection dir,
                                    const ulong closingDeal) const
   {
      if(m_recovery == NULL || m_exec == NULL ||
         closingDeal == 0 || !HistoryDealSelect(closingDeal))
         return false;

      long reason = HistoryDealGetInteger(closingDeal, DEAL_REASON);
      if(reason != DEAL_REASON_SL) return false;
      ulong positionId = (ulong)HistoryDealGetInteger(closingDeal, DEAL_POSITION_ID);
      if(positionId == 0) return false;

      double targetSl = m_recovery.LockTargetPrice(dir);
      double dealPrice = HistoryDealGetDouble(closingDeal, DEAL_PRICE);
      double programmedSl = HistoryDealGetDouble(closingDeal, DEAL_SL);
      double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double spreadPrice = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point;
      if(tickSize <= 0.0 || targetSl <= 0.0) return false;

      double slTolerance = MathMax(2.0 * tickSize, _Point);
      double fillTolerance = MathMax(25.0 * tickSize,
                                     2.0 * spreadPrice + 2.0 * tickSize);
      bool modifyProof = Exec_T14ModifyProofMatches(positionId,
                                                     (long)RecoveryMagic_,
                                                     Recovery_CycleKey(dir),
                                                     targetSl,
                                                     slTolerance);

      return Recovery_ProtectiveSlIdentityPure(true,
                                               true,
                                               reason,
                                               programmedSl,
                                               targetSl,
                                               dealPrice,
                                               slTolerance,
                                               fillTolerance,
                                               modifyProof);
   }

   bool MapClosingDeal(const long ownerMagic,
                       const long dealType,
                       eRecoveryCoreDirection &dir) const
   {
      if(ownerMagic == (long)Magic)
      {
         if(dealType == DEAL_TYPE_SELL) { dir = recovery_CORE_BUY; return true; }
         if(dealType == DEAL_TYPE_BUY)  { dir = recovery_CORE_SELL; return true; }
         return false;
      }
      if(ownerMagic == (long)RecoveryMagic_)
      {
         if(dealType == DEAL_TYPE_BUY)  { dir = recovery_CORE_BUY; return true; }
         if(dealType == DEAL_TYPE_SELL) { dir = recovery_CORE_SELL; return true; }
      }
      return false;
   }

   bool SubmitT16OverlapCoreClose(const int idx,
                                  const ulong ticket,
                                  const long ownerMagic,
                                  string &why)
   {
      why = "";
      if(ticket == 0 || !PositionSelectByTicket(ticket)) return false;
      double volume = PositionGetDouble(POSITION_VOLUME);
      if(volume <= 0.0) return false;

      // Normal EA Core is durable and Recovery-owned for the duration of this
      // expected topology mutation. A deterministic no-effect broker reject is
      // retryable; an ambiguous outcome remains fail-closed.
      if(ownerMagic == (long)Magic)
      {
         eRecoveryCoreDirection dir = Direction(idx);
         int key = Recovery_CycleKey(dir);
         long units = VolumeStepUnits(volume);
         if(!m_recovery.ArmDurableCommand(dir, EXEC_CMD_RECOVERY_CLOSE,
                                          (long)Magic, ticket, units,
                                          CoreMagicUnits(dir), 0.0,
                                          0, 0, why))
            return false;

         bool sent = m_exec.ClosePositionVolumeOwned(ticket, volume,
                                                     (long)Magic, key,
                                                     EXEC_CMD_RECOVERY_CLOSE,
                                                     EXEC_RECONCILE_FAIL_CLOSED);
         if(sent) return true;

         if(m_exec.HasReconcileRequired(key))
         {
            m_cycle[idx].active = false;
            m_cycle[idx].reconcileHold = true;
            why = "T16.2 Overlap Core close outcome ambiguous; reconciliation required";
            return false;
         }

         m_recovery.CancelDurableCommand(dir);
         Log_Warn("Recovery", "t162overlapreject" + (string)key,
                  "T16.2 Overlap Core close bị broker từ chối với outcome xác định không có mutation; giữ cycle và retry");
         why = "Overlap Core close rejected with no broker effect; retry later";
         return true;
      }

      // When flag_Hand_Ord is enabled, BasketManager can include Magic 0.
      // Preserve legacy owner-aware close, but keep the Overlap coordinator
      // latched until that ticket is broker-observably gone.
      bool sent = m_exec.ClosePosition(ticket);
      if(sent)
      {
         m_cycle[idx].legacyPendingTicket = ticket;
         return true;
      }
      why = "T16.2 Overlap manual-managed Core close request rejected";
      return true;
   }

   bool DriveT16OverlapCycle(const int idx,
                             const datetime now,
                             string &why)
   {
      why = "";
      if(!IsT16OverlapCycle(idx)) return false;
      if(m_cycle[idx].reconcileHold && !m_cycle[idx].active)
      {
         why = "T16.2 Overlap mutation remains fail-closed pending explicit reconciliation";
         return true;
      }
      if(!m_cycle[idx].active) return false;
      if(LegacyTicketStillPending(idx)) return true;

      eRecoveryCoreDirection dir = Direction(idx);
      int key = Recovery_CycleKey(dir);
      if(!m_recovery.ActiveReady())
      {
         m_cycle[idx].active = false;
         m_cycle[idx].reconcileHold = true;
         why = "T16.2 Overlap lost Recovery readiness during mutation";
         return true;
      }

      if(m_recovery.HasDurableCommand(dir))
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

      m_exec.ReconcileCycle(key);
      if(m_exec.HasReconcileRequired(key))
      {
         m_cycle[idx].active = false;
         m_cycle[idx].reconcileHold = true;
         why = "T16.2 Overlap execution journal requires reconciliation";
         return true;
      }
      if(m_exec.HasPendingForCycle(key)) return true;

      ulong selectedTicket = 0;
      long selectedOwner = 0;
      if(SpecificTicketLive(idx, selectedTicket, selectedOwner))
      {
         SubmitT16OverlapCoreClose(idx, selectedTicket, selectedOwner, why);
         return true;
      }

      // Both intended Overlap tickets are now broker-observably gone. No Hedge
      // trim is performed: stacked Hedge>Core is intentional. Verify that Core
      // reached the exact target computed at latch time before refreshing ARCS.
      long currentCore = CoreMagicUnits(dir);
      if(currentCore != m_cycle[idx].targetCoreUnits)
      {
         m_cycle[idx].active = false;
         m_cycle[idx].reconcileHold = true;
         why = "T16.2 Overlap Core units differ from expected post-pair target";
         m_recovery.T16LatchExternalMutation(dir, why);
         return true;
      }

      string refreshWhy = "";
      if(!m_recovery.T16FinalizeExpectedOverlapMutation(*m_exec, dir, now, refreshWhy))
      {
         m_cycle[idx].active = false;
         m_cycle[idx].reconcileHold = true;
         why = "T16.2 post-Overlap ARCS refresh failed: " + refreshWhy;
         return true;
      }

      Log_Info("Recovery", "T16.2 coordinated Overlap complete for " +
               Recovery_DirectionName(dir) +
               " — retained Hedge layers preserved; Core/Hedge metrics refreshed");
      ResetCycle(idx);
      return false;
   }

public:
   eRecoveryExitCoordRequest BeginTicketClose(const eRecoveryCoreDirection dir,
                                              const ulong firstTicket,
                                              const ulong secondTicket,
                                              const eRecoveryExitCoordReason reason,
                                              const datetime now)
   {
      if(IsT16Arcs() && m_recovery != NULL)
      {
         SRecoveryCycle cycle;
         m_recovery.GetCycle(dir, cycle);
         bool ownsRecovery = m_recovery.T16HasExposure(dir) ||
                             cycle.state != recovery_CORE_ONLY;

         if(reason == recovery_EXIT_REASON_LEGACY_OVERLAP && ownsRecovery)
         {
            int idx = Index(dir);
            if(!OverlapAfterHedge_)
            {
               Log_Warn("Recovery", "t16overlapoff" + (string)Recovery_CycleKey(dir),
                        "Overlap sau Hedge đang TẮT; giữ nguyên Core trong Recovery cycle");
               return recovery_EXIT_BLOCKED;
            }
            if(m_cycle[idx].reconcileHold) return recovery_EXIT_BLOCKED;
            eRecoveryOverlapPolicy p = Recovery_OverlapPolicyPure(cycle.state);
            if(p == recovery_OVERLAP_DEFER || !m_recovery.ActiveReady())
            {
               Log_Warn("Recovery", "t16overlapdefer" + (string)Recovery_CycleKey(dir),
                        "T16.2 defer Overlap: Recovery đang ở mutation/lock/global/reconcile state");
               return recovery_EXIT_BLOCKED;
            }
            if(p == recovery_OVERLAP_BYPASS && !m_recovery.T16HasExposure(dir))
               return CRecoveryExitCoordinatorT13Base::BeginTicketClose(dir,
                                                                        firstTicket,
                                                                        secondTicket,
                                                                        reason, now);
            if(firstTicket == 0 && secondTicket == 0) return recovery_EXIT_BLOCKED;
            if(m_cycle[idx].active) return recovery_EXIT_LATCHED;

            long currentCore = CoreMagicUnits(dir);
            long intendedCoreClose = CoreMagicUnitsForTicket(dir, firstTicket);
            if(secondTicket != 0 && secondTicket != firstTicket)
               intendedCoreClose += CoreMagicUnitsForTicket(dir, secondTicket);

            m_cycle[idx].active          = true;
            m_cycle[idx].reconcileHold   = false;
            m_cycle[idx].kind            = recovery_EXIT_COORD_TICKETS;
            m_cycle[idx].reason          = reason;
            m_cycle[idx].targetCoreUnits = Recovery_ExitPostCoreUnits(currentCore,
                                                                       intendedCoreClose);
            m_cycle[idx].ticketFirst     = firstTicket;  // Strategy passes last first.
            m_cycle[idx].ticketSecond    = secondTicket;
            m_cycle[idx].ticketCount     = secondTicket != 0 && secondTicket != firstTicket ? 2 : 1;
            m_cycle[idx].startedAt       = now;
            Log_Info("Recovery", "T16.2 Overlap-after-Hedge latched for " +
                     Recovery_DirectionName(dir) +
                     " targetCore=" + DoubleToString(
                        Recovery_UnitsToVolume(m_cycle[idx].targetCoreUnits,
                                               SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP)), 2));
            return recovery_EXIT_LATCHED;
         }

         // Non-Overlap partial topology edits remain forbidden under stacked
         // ownership. Full-side/account-wide risk exits still use T13/T14.
         if(ownsRecovery)
         {
            Log_Warn("Recovery", "t16partial" + (string)Recovery_CycleKey(dir),
                     "T16 ARCS chặn đóng Core từng phần không phải Overlap: phải bảo toàn ownership G1/G2/... và stacked exposure");
            return recovery_EXIT_BLOCKED;
         }
      }
      return CRecoveryExitCoordinatorT13Base::BeginTicketClose(dir,
                                                               firstTicket,
                                                               secondTicket,
                                                               reason,
                                                               now);
   }

   bool Drive(const datetime now, string &why)
   {
      why = "";
      if(!IsT16Arcs()) return CRecoveryExitCoordinatorT13Base::Drive(now, why);

      // Account-wide emergency always preempts Overlap and uses proven base.
      if(m_accountWidePending)
         return CRecoveryExitCoordinatorT13Base::Drive(now, why);

      bool hadOverlap = IsT16OverlapCycle(0) || IsT16OverlapCycle(1);
      if(hadOverlap)
      {
         string w0 = "", w1 = "";
         bool b0 = IsT16OverlapCycle(0) ? DriveT16OverlapCycle(0, now, w0) : false;
         bool b1 = IsT16OverlapCycle(1) ? DriveT16OverlapCycle(1, now, w1) : false;
         if(w0 != "") why = w0;
         if(w1 != "") why = why == "" ? w1 : why + "; " + w1;
         if(b0 || b1 || IsT16OverlapCycle(0) || IsT16OverlapCycle(1)) return true;
         // Overlap completed this call; allow any unrelated base cleanup next.
      }
      return CRecoveryExitCoordinatorT13Base::Drive(now, why);
   }

   bool OnTradeTransaction(const MqlTradeTransaction &trans)
   {
      if(RecoveryMode_ == recovery_ACTIVE && m_recovery != NULL && m_exec != NULL &&
         trans.type == TRADE_TRANSACTION_DEAL_ADD && trans.deal != 0 &&
         trans.symbol == _Symbol && HistoryDealSelect(trans.deal))
      {
         long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
         if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY)
         {
            long ownerMagic = ResolveClosedOwnerMagic(trans.deal);
            if(!HistoryDealSelect(trans.deal)) return true;
            long type = HistoryDealGetInteger(trans.deal, DEAL_TYPE);
            long reason = HistoryDealGetInteger(trans.deal, DEAL_REASON);
            eRecoveryCoreDirection dir = recovery_CORE_BUY;
            bool mapped = MapClosingDeal(ownerMagic, type, dir);

            if(mapped && ownerMagic == (long)RecoveryMagic_)
            {
               int idx = Index(dir);
               bool coordinatorOwned = m_accountWidePending || m_cycle[idx].active;

               if(IsT16Arcs() && !coordinatorOwned &&
                  m_recovery.T16ExpectedBrokerSlDeal(trans.deal))
               {
                  Log_Info("Recovery", "t16sl" + (string)Recovery_CycleKey(dir),
                           "T16 expected ARCS Broker SL executed — layer ownership retained; external latch skipped");
                  return false;
               }

               if(!IsT16Arcs() && !coordinatorOwned &&
                  IsExpectedRecoveryLockSlT14(dir, trans.deal))
               {
                  Log_Info("Recovery", "locksl" + (string)Recovery_CycleKey(dir),
                           "expected Recovery protective SL executed for " +
                           Recovery_DirectionName(dir) +
                           " — T14 durable identity matched; external latch skipped");
                  return false;
               }
            }

            if(IsT16Arcs() && mapped &&
               !m_accountWidePending && !m_cycle[Index(dir)].active &&
               Recovery_ExitExternalDealReason(reason))
            {
               m_recovery.T16LatchExternalMutation(dir,
                  "external/manual close changed ARCS Core/Hedge topology; automatic over-hedge trim is forbidden");
               Log_Warn("Recovery", "t16external" + (string)Recovery_CycleKey(dir),
                        "T16 ARCS external mutation latched FAIL-CLOSED; layer registry requires explicit reconciliation");
               return true;
            }
         }
      }

      return CRecoveryExitCoordinatorT13Base::OnTradeTransaction(trans);
   }
};

#endif // BD_RECOVERY_EXIT_COORDINATOR_T16_WRAPPER_MQH
