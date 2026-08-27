//+------------------------------------------------------------------+
//| StrategyT1714GuardPolicy.mqh — terminal account guard priority   |
//+------------------------------------------------------------------+
#ifndef BD_STRATEGY_T1714_GUARD_POLICY_MQH
#define BD_STRATEGY_T1714_GUARD_POLICY_MQH

#include "MoneyGuard.mqh"

bool Strategy_T1714AccountGuardPreemptsRecoveryPure(
   const eGuardAction action,
   const bool recoveryBlocking)
{
   return recoveryBlocking && action == GUARD_CLOSE_ACCOUNT;
}

#endif // BD_STRATEGY_T1714_GUARD_POLICY_MQH
