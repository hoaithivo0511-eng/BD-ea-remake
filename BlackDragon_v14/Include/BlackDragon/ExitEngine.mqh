//+------------------------------------------------------------------+
//| ExitEngine.mqh — BlackDragon v14.8.0                             |
//| Purpose   : PURE exit decisions: virtual TP / SL / Trailing +    |
//|             Overlap. Returns ExitDecision; never closes orders.  |
//| Invariants: No API calls, no writes. Unit-testable.              |
//+------------------------------------------------------------------+
#ifndef BD_EXITENGINE_MQH
#define BD_EXITENGINE_MQH
#include "Types.mqh"

bool Exit_VirtualTpHit(const bool isBuy, const double tpLevel, const double bid, const double ask)
{
   if(tpLevel == 0) return false;
   return isBuy ? (bid >= tpLevel) : (ask <= tpLevel);
}

bool Exit_VirtualSlHit(const bool isBuy, const double slLevel, const double bid, const double ask)
{
   if(slLevel == 0) return false;
   return isBuy ? (bid <= slLevel) : (ask >= slLevel);
}

bool Exit_TrailHit(const bool isBuy, const bool armed, const double trailLevel,
                   const double bid, const double ask)
{
   if(!armed || trailLevel == 0) return false;
   return isBuy ? (bid <= trailLevel) : (ask >= trailLevel);
}

bool Exit_OverlapHit(const int count, const int overlapFromOrder, const bool overlapOn,
                     const double firstProfit, const double lastProfit, const double overlapPercent)
{
   if(!overlapOn || count < overlapFromOrder) return false;
   if(firstProfit >= 0) return false;
   return lastProfit > 0 && lastProfit >= -firstProfit * (100.0 + overlapPercent) / 100.0;
}

class CVirtualExitPolicy
{
public:
   ExitDecision Check(const EAContext &ctx, const BasketSide &side, const int dir)
   {
      ExitDecision d;
      d.kind = EXIT_NONE;
      d.direction = dir;
      d.pairFirst = 0;
      d.pairLast = 0;
      if(side.count == 0) return d;
      bool isBuy = (dir == 0);

      if(TP_Mode == mode_Virt && Exit_VirtualTpHit(isBuy, side.tpLevel, ctx.bid, ctx.ask))
      { d.kind = EXIT_TP; return d; }
      if(SL_Mode == mode_Virt && Exit_VirtualSlHit(isBuy, side.slLevel, ctx.bid, ctx.ask))
      { d.kind = EXIT_SL; return d; }
      if(Trail_Mode == mode_Virt && Exit_TrailHit(isBuy, side.trailArmed, side.trailLevel, ctx.bid, ctx.ask))
      { d.kind = EXIT_TRAIL; return d; }

      if(Exit_OverlapHit(side.count, OverlapOrderNumber, Overlap,
                         side.pos[0].profit, side.pos[side.count - 1].profit, OverlapPercent))
      {
         d.kind      = EXIT_OVERLAP;
         d.pairFirst = side.pos[0].ticket;
         d.pairLast  = side.pos[side.count - 1].ticket;
         return d;
      }
      return d;
   }

   bool RealLevels(const EAContext &ctx, const BasketSide &side, const bool isBuy,
                   double &sl, double &tp)
   {
      sl = 0;
      tp = 0;
      if(TP_Mode == mode_Virt && SL_Mode == mode_Virt && Trail_Mode == mode_Virt) return false;
      if(side.count == 0) return false;
      if(TP_Mode == mode_Real && Cfg.TP != 0) tp = side.tpLevel;
      if(SL_Mode == mode_Real && Cfg.SL != 0) sl = side.slLevel;
      if(Trail_Mode == mode_Real && side.trailArmed)
      {
         if(isBuy  && side.trailLevel > sl)              sl = side.trailLevel;
         if(!isBuy && (side.trailLevel < sl || sl == 0)) sl = side.trailLevel;
      }
      sl = NormalizeDouble(sl, ctx.digits);
      tp = NormalizeDouble(tp, ctx.digits);
      return true;
   }
};
#endif // BD_EXITENGINE_MQH
