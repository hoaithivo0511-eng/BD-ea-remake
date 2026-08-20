//+------------------------------------------------------------------+
//| RecoveryT165Policy.mqh — T16.5 pure safety/valuation policies    |
//| Keeps broker-effect taxonomy independent from runtime plumbing.  |
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_T165_POLICY_MQH
#define BD_RECOVERY_T165_POLICY_MQH

#include "RecoveryT16Config.mqh"

enum eRecoveryT165CapacityDisposition
{
   RECOVERY_T165_CAPACITY_EXECUTE = 0,
   RECOVERY_T165_CAPACITY_WAIT_NO_EFFECT,
   RECOVERY_T165_CAPACITY_RECONCILE
};

// Preflight failures and explicit rejected sends have a known no-effect
// outcome. Only an ambiguous broker outcome requires reconciliation.
eRecoveryT165CapacityDisposition Recovery_T165CapacityDispositionPure(
   const bool preflightAllows,
   const bool requestAccepted,
   const bool outcomeAmbiguous)
{
   if(outcomeAmbiguous) return RECOVERY_T165_CAPACITY_RECONCILE;
   if(!preflightAllows || !requestAccepted)
      return RECOVERY_T165_CAPACITY_WAIT_NO_EFFECT;
   return RECOVERY_T165_CAPACITY_EXECUTE;
}

// Guard economic side = Core basket + the Recovery Hedge owned by that Core
// direction. This is the valuation scope that a coordinated side close mutates.
double Recovery_T165EconomicSideProfitPure(const double coreProfit,
                                           const double recoveryHedgeProfit)
{
   return coreProfit + recoveryHedgeProfit;
}

double Recovery_T165MagicNetPure(const double coreBuyProfit,
                                 const double coreSellProfit,
                                 const double recoveryForBuyProfit,
                                 const double recoveryForSellProfit)
{
   return Recovery_T165EconomicSideProfitPure(coreBuyProfit, recoveryForBuyProfit) +
          Recovery_T165EconomicSideProfitPure(coreSellProfit, recoveryForSellProfit);
}

bool Recovery_T165PctDiffHitPure(const double buyEconomicProfit,
                                 const double sellEconomicProfit,
                                 const double pct)
{
   if(pct <= 0.0) return false;
   double win  = MathMax(buyEconomicProfit, sellEconomicProfit);
   double lose = MathMin(buyEconomicProfit, sellEconomicProfit);
   if(lose >= 0.0) return false;
   return win + lose * (1.0 + pct / 100.0) >= 0.0;
}

bool Recovery_T165MarginReserveAllowsPure(const double freeMargin,
                                          const double dcaMargin,
                                          const double hedgeMargin)
{
   if(freeMargin < 0.0 || dcaMargin < 0.0 || hedgeMargin < 0.0) return false;
   return freeMargin + 1e-9 >= dcaMargin + hedgeMargin;
}

int Recovery_T165WaitLogSecondsPure(const int configured)
{
   if(configured < 0) return 0;
   if(configured > 86400) return 86400;
   return configured;
}

#endif // BD_RECOVERY_T165_POLICY_MQH
