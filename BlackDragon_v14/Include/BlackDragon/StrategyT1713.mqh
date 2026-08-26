//+------------------------------------------------------------------+
//| StrategyT1713.mqh — non-exclusive Overlap Core-growth adapter   |
//| Reuses exact T17.12 Strategy; remaps only side-growth admission. |
//+------------------------------------------------------------------+
#ifndef BD_STRATEGY_T1713_MQH
#define BD_STRATEGY_T1713_MQH

// Preload the T17.13 coordinator so Strategy.mqh's include is guard-skipped.
#include "Overlap/OverlapT177Coordinator.mqh"

// Existing Strategy uses BlocksSide only for new same-side opens. T17.13
// narrows that admission to actual broker mutation/reconcile while preserving
// every other ordering/exit/guard branch byte-for-behavior.
#define BlocksSide BlocksCoreGrowth
#include "Strategy.mqh"
#undef BlocksSide

#endif // BD_STRATEGY_T1713_MQH
