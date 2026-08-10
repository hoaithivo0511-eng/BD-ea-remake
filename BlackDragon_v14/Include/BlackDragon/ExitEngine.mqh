//+------------------------------------------------------------------+
//| ExitEngine.mqh — BlackDragon v14.0.0                             |
//| Purpose   : PURE exit decisions: virtual TP / SL / Trailing +    |
//|             Overlap. Returns ExitDecision; never closes orders.  |
//| Invariants: No API calls, no writes. Unit-testable (P1).         |
//| Fixes     : #2 trailing 100pt gap window removed (gap through    |
//|             the level now still closes), #10 overlap requires    |
//|             first order LOSING (v13 also fired when profitable). |
//| Depends on: Types.mqh                                            |
//| [STRATEGY-BEHAVIOR] Comparison directions are v13 behavior.      |
//+------------------------------------------------------------------+
#ifndef BD_EXITENGINE_MQH
#define BD_EXITENGINE_MQH
#include "Types.mqh"

//--- Virtual TP: Bid >= tp(buy) / Ask <= tp(sell) --------------------
bool Exit_VirtualTpHit(const bool isBuy, const double tpLevel, const double bid, const double ask)
{
   if(tpLevel == 0) return false;
   return isBuy ? (bid >= tpLevel) : (ask <= tpLevel);
}

//--- Virtual SL: Bid <= sl(buy) / Ask >= sl(sell) --------------------
bool Exit_VirtualSlHit(const bool isBuy, const double slLevel, const double bid, const double ask)
{
   if(slLevel == 0) return false;
   return isBuy ? (bid <= slLevel) : (ask >= slLevel);
}

//--- Virtual trailing. Fix #2: v13 required price to sit INSIDE a    |
//    100-point window below/above the level; a fast gap jumped over  |
//    it and the basket never closed. v14: crossing is enough.        |
bool Exit_TrailHit(const bool isBuy, const bool armed, const double trailLevel,
                   const double bid, const double ask)
{
   if(!armed || trailLevel == 0) return false;
   return isBuy ? (bid <= trailLevel) : (ask >= trailLevel);
}

//--- Overlap: last order profit covers first order loss + percent ---
//    Fix #10: require firstProfit < 0 (a losing first order). v13    |
//    fired even when the first order was profitable, closing the    |
//    best two orders of the basket for no reason.                   |
bool Exit_OverlapHit(const int count, const int overlapFromOrder, const bool overlapOn,
                     const double firstProfit, const double lastProfit, const int overlapPercent)
{
   if(!overlapOn || count < overlapFromOrder) return false;
   if(firstProfit >= 0) return false;   // fix #10
   return lastProfit > 0 && lastProfit >= -firstProfit * (100 + overlapPercent) / 100.0;
}

//--- Coordinator-facing policy ---------------------------------------
class CVirtualExitPolicy
{
public:
   // Returns first matching decision for one side. dir: 0=buy, 1=sell
   ExitDecision Check(const EAContext &ctx, const BasketSide &side, const int dir)
   {
      ExitDecision d;
      d.kind = EXIT_NONE; d.direction = dir; d.pairFirst = 0; d.pairLast = 0;
      if(side.count == 0) return d;
      bool isBuy = (dir == 0);

      if(TP_Mode == mode_Virt && Exit_VirtualTpHit(isBuy, side.tpLevel, ctx.bid, ctx.ask))
      { d.kind = EXIT_TP; return d; }

      if(SL_Mode == mode_Virt && Exit_VirtualSlHit(isBuy, side.slLevel, ctx.bid, ctx.ask))
      { d.kind = EXIT_SL; return d; }

      if(Trail_Mode == mode_Virt && Exit_TrailHit(isBuy, side.trailArmed, side.trailLevel, ctx.bid, ctx.ask))
      { d.kind = EXIT_TRAIL; return d; }

      if(Exit_OverlapHit(side.count, OverlapOrderNumber, Overlap,
                         side.pos[0].profit, side.pos[side.count-1].profit, OverlapPercent))
      {
         d.kind      = EXIT_OVERLAP;
         d.pairFirst = side.pos[0].ticket;
         d.pairLast  = side.pos[side.count-1].ticket;
         return d;
      }
      return d;
   }

   // Real-mode TP/SL/Trail levels to push onto positions (v13 TP_SL_TRAIL)
   bool RealLevels(const EAContext &ctx, const BasketSide &side, const bool isBuy,
                   double &sl, double &tp)
   {
      sl = 0; tp = 0;
      if(TP_Mode == mode_Virt && SL_Mode == mode_Virt && Trail_Mode == mode_Virt) return false;
      if(side.count == 0) return false;
      if(TP_Mode == mode_Real && Cfg.TP != 0) tp = side.tpLevel;
      if(SL_Mode == mode_Real && Cfg.SL != 0) sl = side.slLevel;
      if(Trail_Mode == mode_Real && side.trailArmed)
      {
         if(isBuy  && side.trailLevel > sl)               sl = side.trailLevel;
         if(!isBuy && (side.trailLevel < sl || sl == 0))  sl = side.trailLevel;
      }
      sl = NormalizeDouble(sl, ctx.digits);
      tp = NormalizeDouble(tp, ctx.digits);
      return true;
   }
};
#endif // BD_EXITENGINE_MQH
