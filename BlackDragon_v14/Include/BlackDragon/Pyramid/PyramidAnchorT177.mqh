//+------------------------------------------------------------------+
//| PyramidAnchorT177.mqh — T17.7 C2 Core Pyramid anchor policy     |
//| DYNAMIC preserves T17.6; FIRST_CORE uses cumulative distances.   |
//+------------------------------------------------------------------+
#ifndef BD_PYRAMID_ANCHOR_T177_MQH
#define BD_PYRAMID_ANCHOR_T177_MQH

#include "PyramidConfig.mqh"

enum eCorePyramidAnchorMode
{
   pyramid_anchor_DYNAMIC = 0,
   pyramid_anchor_FIRST_CORE_CUMULATIVE = 1
};

input group "23B — MỐC NHỒI DƯƠNG CORE (T17.7)"
input eCorePyramidAnchorMode CorePyramidAnchorMode_ = pyramid_anchor_DYNAMIC; // DYNAMIC giữ logic cũ; FIRST_CORE giữ mốc lệnh Core đầu campaign

#define BD_T177_ANCHOR_POLICY_REV 1

bool Pyramid_T177AnchorModeValid(const eCorePyramidAnchorMode mode)
{
   return mode == pyramid_anchor_DYNAMIC ||
          mode == pyramid_anchor_FIRST_CORE_CUMULATIVE;
}

string Pyramid_T177AnchorModeName(const eCorePyramidAnchorMode mode)
{
   if(mode == pyramid_anchor_DYNAMIC) return "DYNAMIC";
   if(mode == pyramid_anchor_FIRST_CORE_CUMULATIVE) return "FIRST_CORE_CUMULATIVE";
   return "INVALID";
}

// DistanceSequence is interpreted as per-serial increments. When serial goes
// past the explicit sequence, the last configured distance repeats, matching
// Pyramid_SeqValue() compatibility semantics.
double Pyramid_T177CumulativeDistancePure(const double &distance[],
                                          const int serialLevel)
{
   if(serialLevel <= 0 || ArraySize(distance) <= 0) return 0.0;
   double total = 0.0;
   for(int i = 0; i < serialLevel; i++)
      total += Pyramid_SeqValue(distance, i);
   return total;
}

double Pyramid_T177FirstCoreTriggerPricePure(const int dir,
                                             const double firstCorePrice,
                                             const double cumulativeDistancePrice)
{
   if(firstCorePrice <= 0.0 || cumulativeDistancePrice < 0.0) return 0.0;
   return dir == 0 ? firstCorePrice + cumulativeDistancePrice
                   : firstCorePrice - cumulativeDistancePrice;
}

bool Pyramid_T177FirstCoreGapHitPure(const int dir,
                                     const double firstCorePrice,
                                     const double bid,
                                     const double ask,
                                     const double cumulativeDistancePrice)
{
   if(firstCorePrice <= 0.0 || bid <= 0.0 || ask <= 0.0 ||
      cumulativeDistancePrice < 0.0)
      return false;
   double target = Pyramid_T177FirstCoreTriggerPricePure(dir, firstCorePrice,
                                                         cumulativeDistancePrice);
   if(target <= 0.0) return false;
   return dir == 0 ? ask + 1e-12 >= target
                   : bid - 1e-12 <= target;
}

// Compatibility-sensitive semantic wrapper. The default DYNAMIC mode returns
// the exact historical Pyramid semantic string, so upgrading without changing
// the new input does NOT rotate the T16/ARCS persistence identity. A non-default
// FIRST_CORE mode receives an explicit revision + mode token.
string Pyramid_T177ExtendedSemanticText()
{
   string legacy = Pyramid_SemanticText();
   if(CorePyramidAnchorMode_ == pyramid_anchor_DYNAMIC) return legacy;
   return legacy +
          "|t177AnchorRev=" + (string)BD_T177_ANCHOR_POLICY_REV +
          "|coreAnchorMode=" + (string)(int)CorePyramidAnchorMode_;
}

#endif // BD_PYRAMID_ANCHOR_T177_MQH
