//+------------------------------------------------------------------+
//| RecoveryMath.mqh — Adaptive Recovery Hedge T1 foundation         |
//| Purpose   : Pure counting/unit/price helpers only.               |
//| Invariants: No trade API, no broker mutation, no global state.   |
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_MATH_MQH
#define BD_RECOVERY_MATH_MQH

#include <BlackDragon/Config.mqh>

// Initial Core order is NOT a DCA. Negative/flat counts are treated as 0.
int Recovery_DcaCountFromCoreCount(const int coreOpenCount)
{
   if(coreOpenCount <= 1) return 0;
   return coreOpenCount - 1;
}

// Threshold 0 means "after zero DCA" => arm as soon as a Core position exists.
// Negative thresholds are invalid and never arm.
bool Recovery_DcaThresholdReached(const int coreOpenCount, const int startAfterDca)
{
   if(coreOpenCount <= 0 || startAfterDca < 0) return false;
   return Recovery_DcaCountFromCoreCount(coreOpenCount) >= startAfterDca;
}

// Convert requested volume to broker-step units without ever rounding upward.
long Recovery_VolumeToUnitsFloor(const double volume, const double volumeStep)
{
   if(volume <= 0.0 || volumeStep <= 0.0) return 0;
   // Tiny epsilon protects exact-grid values such as 0.30/0.10 from binary
   // representation drift while preserving the required floor for 0.245/0.01.
   return (long)MathFloor(volume / volumeStep + 1e-9);
}

double Recovery_UnitsToVolume(const long units, const double volumeStep)
{
   if(units <= 0 || volumeStep <= 0.0) return 0.0;
   return NormalizeDouble((double)units * volumeStep, 8);
}

// Shared price convention for Recovery. Gold reuses BlackDragon's canonical
// BD_POINTS_PER_PIP=10 reference where one reference point = 0.01 price,
// therefore one XAU pip = 0.10 price on both 2- and 3-digit quotes.
double Recovery_PipSizePure(const bool isGold, const double point, const int digits)
{
   if(point <= 0.0) return 0.0;
   if(isGold) return 0.01 * BD_POINTS_PER_PIP;
   return (digits == 3 || digits == 5) ? point * 10.0 : point;
}

double Recovery_PipsToPricePure(const double pips, const bool isGold,
                                const double point, const int digits)
{
   return pips * Recovery_PipSizePure(isGold, point, digits);
}

long Recovery_PriceToTicksPure(const double price, const double tickSize)
{
   if(tickSize <= 0.0) return 0;
   return (long)MathRound(price / tickSize);
}

long Recovery_PipsToTicksPure(const double pips, const bool isGold,
                              const double point, const int digits,
                              const double tickSize)
{
   if(tickSize <= 0.0) return 0;
   double dist = Recovery_PipsToPricePure(pips, isGold, point, digits);
   return (long)MathRound(dist / tickSize);
}

#endif // BD_RECOVERY_MATH_MQH
