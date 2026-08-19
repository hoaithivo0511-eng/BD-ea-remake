//+------------------------------------------------------------------+
//| RecoveryExitCoordinator.mqh — T14 identity + T16 ARCS wrapper    |
//| T13 remains pinned. T16 intercepts only semantics that conflict  |
//| with intentional stacked over-hedge / generation ownership.      |
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

public:
   // T16: a partial legacy/Overlap Core trim cannot be delegated to the T13
   // cap rule because T13 defines Hedge>Core as excess. In ARCS stacked mode
   // that over-hedge is intentional and layer-owned. Defer partial topology
   // edits once ARCS owns exposure; full-side/account-wide risk exits still
   // delegate to T13 and are allowed to flatten the whole Hedge stack first.
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
         if(m_recovery.T16HasExposure(dir) || cycle.state != recovery_CORE_ONLY)
         {
            Log_Warn("Recovery", "t16partial" + (string)Recovery_CycleKey(dir),
                     "T16 ARCS chặn đóng Core từng phần từ subsystem legacy: phải bảo toàn ownership G1/G2/... và stacked exposure");
            return recovery_EXIT_BLOCKED;
         }
      }
      return CRecoveryExitCoordinatorT13Base::BeginTicketClose(dir,
                                                               firstTicket,
                                                               secondTicket,
                                                               reason,
                                                               now);
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

               // T16 Broker-SL is generation/global owned. The ARCS engine must
               // consume this deal so it can update layer cash/state. Do not
               // classify an expected protective SL as external intervention.
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

            // T16 unknown/manual/broker mutation: never run the T13 automatic
            // 'excess Hedge = Hedge-Core' trim because stacked Hedge>Core is a
            // valid architecture state. Unknown topology is fail-closed and
            // must be explicitly reconciled instead.
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

      // Full-side/account-wide emergency exits and exact legacy contract keep
      // the proven T13/T14 coordinator path.
      return CRecoveryExitCoordinatorT13Base::OnTradeTransaction(trans);
   }
};

#endif // BD_RECOVERY_EXIT_COORDINATOR_T16_WRAPPER_MQH
