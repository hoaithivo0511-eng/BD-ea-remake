//+------------------------------------------------------------------+
//| RecoveryExitCoordinator.mqh — T14 identity compatibility layer   |
//|                                                                   |
//| T13 coordinator is pinned byte-for-byte in                       |
//| RecoveryExitCoordinatorT13Base.mqh. T14 intercepts only the      |
//| confirmed protective-SL classifier; every other T8/T12/T13 path |
//| delegates unchanged to the pinned base implementation.           |
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_EXIT_COORDINATOR_T14_WRAPPER_MQH
#define BD_RECOVERY_EXIT_COORDINATOR_T14_WRAPPER_MQH

// Preload dependencies before exposing the pinned base's private section as
// protected for this narrow derived compatibility layer.
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

      // Programmed stop itself should match tightly; execution price may slip
      // around the stop, so retain the bounded T10 fill window.
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

public:
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
            if(ownerMagic == (long)RecoveryMagic_ && HistoryDealSelect(trans.deal))
            {
               long type = HistoryDealGetInteger(trans.deal, DEAL_TYPE);
               eRecoveryCoreDirection dir = recovery_CORE_BUY;
               bool mapped = true;
               if(type == DEAL_TYPE_BUY) dir = recovery_CORE_BUY;        // closes SELL hedge
               else if(type == DEAL_TYPE_SELL) dir = recovery_CORE_SELL;// closes BUY hedge
               else mapped = false;

               if(mapped)
               {
                  int idx = Index(dir);
                  bool coordinatorOwned = m_accountWidePending || m_cycle[idx].active;
                  if(!coordinatorOwned && IsExpectedRecoveryLockSlT14(dir, trans.deal))
                  {
                     Log_Info("Recovery", "locksl" + (string)Recovery_CycleKey(dir),
                              "expected Recovery protective SL executed for " +
                              Recovery_DirectionName(dir) +
                              " — T14 durable identity matched; external latch skipped");
                     return false;
                  }
               }
            }
         }
      }

      // Unknown/manual/random SL and every non-SL mutation retain the exact
      // T13 fail-closed classifier and coordinator behavior.
      return CRecoveryExitCoordinatorT13Base::OnTradeTransaction(trans);
   }
};

#endif // BD_RECOVERY_EXIT_COORDINATOR_T14_WRAPPER_MQH
