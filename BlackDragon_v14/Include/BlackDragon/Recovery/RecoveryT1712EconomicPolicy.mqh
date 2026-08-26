//+------------------------------------------------------------------+
//| RecoveryT1712EconomicPolicy.mqh — recovery-aware exit economics |
//| Pure policy only. No trade mutation, persistence or new inputs. |
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_T1712_ECONOMIC_POLICY_MQH
#define BD_RECOVERY_T1712_ECONOMIC_POLICY_MQH

struct SRecoveryT1712ExitEconomicSnapshot
{
   bool   recoveryOwns;
   bool   valid;
   double coreFloating;
   double recoveryFloating;
   double pyramidRealized;
   double recoveryCycleRealized;
   double coreLots;
   double recoveryLots;
   int    closeRequests;
   double requiredTargetCash;
   double reserveCash;
   double currentExitPrice;
   double netCashSlopePerPrice;
};

void Recovery_T1712SnapshotReset(SRecoveryT1712ExitEconomicSnapshot &s)
{
   ZeroMemory(s);
   s.valid = false;
   s.reserveCash = DBL_MAX;
}

bool Recovery_T1712FinitePure(const double v)
{
   return v > -DBL_MAX / 4.0 && v < DBL_MAX / 4.0;
}

double Recovery_T1712NominalTargetCashPure(const double tpPrice,
                                           const double breakevenPrice,
                                           const double totalLots,
                                           const double tickSize,
                                           const double tickValue)
{
   if(tpPrice <= 0.0 || breakevenPrice <= 0.0 || totalLots <= 0.0 ||
      tickSize <= 0.0 || tickValue <= 0.0)
      return DBL_MAX;
   return MathAbs(tpPrice - breakevenPrice) / tickSize * tickValue * totalLots;
}

double Recovery_T1712LiquidationReserveCashPure(const double spreadPrice,
                                                 const double deviationPrice,
                                                 const double totalLots,
                                                 const int closeRequests,
                                                 const double tickSize,
                                                 const double tickValue)
{
   if(tickSize <= 0.0 || tickValue <= 0.0) return DBL_MAX;
   if(totalLots <= 0.0) return 0.0;
   int requests = closeRequests > 0 ? closeRequests : 1;
   double spread = MathMax(spreadPrice, tickSize);
   double move = 2.0 * spread + MathMax(deviationPrice, 0.0) * requests;
   double cash = move / tickSize * tickValue * totalLots;
   return Recovery_T1712FinitePure(cash) ? cash : DBL_MAX;
}

double Recovery_T1712CashSlopePerPricePure(const bool isBuy,
                                            const double coreLots,
                                            const double recoveryOppositeLots,
                                            const double tickSize,
                                            const double tickValue)
{
   if(coreLots <= 0.0 || recoveryOppositeLots < 0.0 ||
      tickSize <= 0.0 || tickValue <= 0.0)
      return 0.0;
   double directional = (coreLots - recoveryOppositeLots) * tickValue / tickSize;
   return isBuy ? directional : -directional;
}

double Recovery_T1712SnapshotCashPure(const SRecoveryT1712ExitEconomicSnapshot &s)
{
   return s.coreFloating + s.recoveryFloating +
          s.pyramidRealized + s.recoveryCycleRealized;
}

bool Recovery_T1712ExitFundedPure(const bool recoveryOwns,
                                  const bool valid,
                                  const double coreFloating,
                                  const double recoveryFloating,
                                  const double pyramidRealized,
                                  const double requiredTargetCash,
                                  const double reserveCash,
                                  const double recoveryCycleRealized=0.0)
{
   if(!recoveryOwns) return true;
   if(!valid || !Recovery_T1712FinitePure(reserveCash) ||
      !Recovery_T1712FinitePure(requiredTargetCash) ||
      !Recovery_T1712FinitePure(coreFloating) ||
      !Recovery_T1712FinitePure(recoveryFloating) ||
      !Recovery_T1712FinitePure(pyramidRealized) ||
      !Recovery_T1712FinitePure(recoveryCycleRealized))
      return false;
   double required = MathMax(requiredTargetCash, 0.0) + MathMax(reserveCash, 0.0);
   double economic = coreFloating + recoveryFloating + pyramidRealized +
                     recoveryCycleRealized;
   return economic + 1e-9 >= required;
}

bool Recovery_T1712SnapshotFundedPure(const SRecoveryT1712ExitEconomicSnapshot &s)
{
   return Recovery_T1712ExitFundedPure(s.recoveryOwns, s.valid,
                                       s.coreFloating, s.recoveryFloating,
                                       s.pyramidRealized, s.requiredTargetCash,
                                       s.reserveCash, s.recoveryCycleRealized);
}

bool Recovery_T1712ProjectedPriceFundedPure(const SRecoveryT1712ExitEconomicSnapshot &s,
                                            const double targetPrice)
{
   if(!s.recoveryOwns) return true;
   if(!s.valid || targetPrice <= 0.0 || s.currentExitPrice <= 0.0 ||
      !Recovery_T1712FinitePure(targetPrice) ||
      !Recovery_T1712FinitePure(s.netCashSlopePerPrice) ||
      !Recovery_T1712FinitePure(s.reserveCash) ||
      !Recovery_T1712FinitePure(s.requiredTargetCash))
      return false;
   double projected = Recovery_T1712SnapshotCashPure(s) +
                      s.netCashSlopePerPrice * (targetPrice - s.currentExitPrice);
   double required = MathMax(s.requiredTargetCash,0.0) + MathMax(s.reserveCash,0.0);
   return Recovery_T1712FinitePure(projected) && projected + 1e-9 >= required;
}

// Project from current executable Core-side price to an outward broker TP.
// If net economic slope is flat/adverse in the Core-favorable direction there
// is no finite safe broker TP: caller must leave Core TP unprogrammed.
bool Recovery_T1712ProjectedTpPure(const bool isBuy,
                                   const double currentExitPrice,
                                   const double legacyTp,
                                   const double currentCoreFloating,
                                   const double currentRecoveryFloating,
                                   const double pyramidRealized,
                                   const double requiredTargetCash,
                                   const double reserveCash,
                                   const double netCashSlopePerPrice,
                                   double &projectedTp,
                                   const double recoveryCycleRealized=0.0)
{
   projectedTp = 0.0;
   if(currentExitPrice <= 0.0 || legacyTp <= 0.0 ||
      !Recovery_T1712FinitePure(currentCoreFloating) ||
      !Recovery_T1712FinitePure(currentRecoveryFloating) ||
      !Recovery_T1712FinitePure(pyramidRealized) ||
      !Recovery_T1712FinitePure(recoveryCycleRealized) ||
      !Recovery_T1712FinitePure(requiredTargetCash) ||
      !Recovery_T1712FinitePure(reserveCash) ||
      !Recovery_T1712FinitePure(netCashSlopePerPrice))
      return false;

   double required = MathMax(requiredTargetCash, 0.0) + MathMax(reserveCash, 0.0);
   double currentEconomic = currentCoreFloating + currentRecoveryFloating +
                            pyramidRealized + recoveryCycleRealized;
   double atLegacy = currentEconomic +
                     netCashSlopePerPrice * (legacyTp - currentExitPrice);
   if(atLegacy + 1e-9 >= required)
   {
      projectedTp = legacyTp;
      return true;
   }

   double favorableSlope = netCashSlopePerPrice * (isBuy ? 1.0 : -1.0);
   if(favorableSlope <= 1e-12) return false;
   double move = (required - atLegacy) / favorableSlope;
   if(move < 0.0 || !Recovery_T1712FinitePure(move)) return false;
   projectedTp = legacyTp + (isBuy ? move : -move);
   if(projectedTp <= 0.0 || !Recovery_T1712FinitePure(projectedTp))
   { projectedTp = 0.0; return false; }
   if(isBuy && projectedTp + 1e-12 < legacyTp)
   { projectedTp = 0.0; return false; }
   if(!isBuy && projectedTp > legacyTp + 1e-12)
   { projectedTp = 0.0; return false; }
   return true;
}

#endif // BD_RECOVERY_T1712_ECONOMIC_POLICY_MQH
