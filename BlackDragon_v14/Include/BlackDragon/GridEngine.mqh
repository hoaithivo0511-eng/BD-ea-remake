//+------------------------------------------------------------------+
//| GridEngine.mqh — BlackDragon v14.0.0                             |
//| Purpose   : PURE functions: grid distance, martingale lot,       |
//|             volume normalization. Unit-testable (P1).            |
//| Invariants: No global reads besides Config inputs. No orders.    |
//| Depends on: Config.mqh, Types.mqh                                |
//| [STRATEGY-BEHAVIOR] All formulas are v13 behavior. Changing them |
//|                     changes the strategy — route via ILotSizer.  |
//+------------------------------------------------------------------+
#ifndef BD_GRIDENGINE_MQH
#define BD_GRIDENGINE_MQH
#include "Types.mqh"

//--- v13 OPEN_ORDERS distance rule -----------------------------------
// count < Order_dinamic_distance-1 -> Fix_Distance
// else round(Dynamic_distance_start * Distance_multiplier^(count+1-Order_dinamic_distance))
int Grid_DistancePoints(const int count,
                        const int fixDistance,
                        const int dynStartOrder,
                        const int dynStartDistance,
                        const double multiplier)
{
   if(count < dynStartOrder - 1) return fixDistance;
   return (int)NormalizeDouble(dynStartDistance * MathPow(multiplier, count + 1 - dynStartOrder), 0);
}

//--- v13 martingale: nLot = NormalizeDouble(firstLot * Martin^count, 2)
double Grid_MartingaleLot(const double firstLot, const int count, const double martin, const double maxLot)
{
   double lot = NormalizeDouble(firstLot * MathPow(martin, count), BD_LOT_DIGITS);
   if(lot > maxLot) lot = maxLot;
   return lot;
}

//--- v13 first lot: Lot_Init, or FreeMargin/Autolotsize*0.01 when Autolot
double Grid_FirstLot(const double lotInit, const bool autolot, const int autolotSize,
                     const double freeMargin, const double maxLot)
{
   double lot = lotInit;
   if(autolot && autolotSize > 0) lot = freeMargin / autolotSize * 0.01;
   if(lot > maxLot) lot = maxLot;
   return lot;
}

//--- Broker constraints (fix: clamp to SYMBOL_VOLUME_MIN/MAX/STEP)
double Grid_NormalizeVolume(double lot)
{
   double vMin  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vMax  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double vStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(vStep > 0) lot = MathFloor(lot / vStep + 0.5) * vStep;
   if(lot < vMin) lot = vMin;
   if(lot > vMax) lot = vMax;
   return NormalizeDouble(lot, 8);
}

//--- v14.1 FE-201: gold pip convention --------------------------------
//    Quy uoc: 1 gia (1 USD) = 10 pips -> 1 pip = 0.1 USD.
//    Reference quote = gold 2 digits (point 0.01). Returns how many broker
//    points equal ONE reference point, so every point-based input written
//    for a 2-digit gold chart behaves identically on a 3-digit broker
//    (200 input points = 2.00 USD = 20 pips everywhere). Non-gold: 1.
int Sym_PointScalePure(const bool isGold, const double point)
{
   if(!isGold || point <= 0) return 1;
   int k = (int)MathRound(0.01 / point);   // 2-digit: 1, 3-digit: 10
   return k < 1 ? 1 : k;
}

//--- BD-R2 (v14.7.2): explicit-symbol variants -----------------------
//    FE-401 CloseAllAccount and ClosePositionEx act on positions of ANY
//    symbol, so a point-based input used there must be scaled with THAT
//    symbol's point size, not the chart's. The _Symbol wrappers below are
//    byte-for-byte equivalent to the previous implementation.
bool Sym_IsGoldSym(const string sym)
{
   string name = sym;
   StringToUpper(name);
   return SymbolInfoString(sym, SYMBOL_CURRENCY_BASE) == "XAU" ||
          StringFind(name, "XAU") >= 0 || StringFind(name, "GOLD") >= 0;
}

bool Sym_IsGold()
{
   return Sym_IsGoldSym(_Symbol);
}

int Sym_PointScaleFor(const string sym)
{
   if(!AutoGoldPip) return 1;
   return Sym_PointScalePure(Sym_IsGoldSym(sym), SymbolInfoDouble(sym, SYMBOL_POINT));
}

int Sym_PointScale()
{
   return Sym_PointScaleFor(_Symbol);
}

//--- v14.1/14.2 FE-202+FE-301: manual DCA lot sequence ----------------
//    Parse "0.01-0.02-0.04" or "0.01x5-0.02x3-0.05" -> flat lots[].
//    '-' separates steps; an optional xN/XN suffix repeats a step N times
//    (0.01x5 -> five orders at 0.01). Spaces are ignored anywhere.
//    Returns element count after expansion; 0 = invalid: empty token,
//    non-numeric lot, lot <= 0, zero/non-integer repeat, or expansion
//    beyond BD_MAX_LOT_STEPS. '-' is the separator, so negative numbers
//    can never sneak in. Strict char check: MQL5 StringToDouble ignores
//    trailing garbage ("0.01a" -> 0.01), so we refuse it explicitly.
//    (BD_MAX_LOT_STEPS lives in Config.mqh with the other constants — FIX-6.)
int Grid_ParseLotSequence(const string seq, double &lots[])
{
   ArrayResize(lots, 0);
   string s = seq;
   StringReplace(s, " ", "");
   if(StringLen(s) == 0) return 0;
   string parts[];
   int n = StringSplit(s, '-', parts);
   for(int i = 0; i < n; i++)
   {
      string p = parts[i];
      if(StringLen(p) == 0) { ArrayResize(lots, 0); return 0; }

      int rep = 1;
      int xp = StringFind(p, "x");
      if(xp < 0) xp = StringFind(p, "X");
      if(xp >= 0)
      {
         string cnt = StringSubstr(p, xp + 1);
         p = StringSubstr(p, 0, xp);
         if(StringLen(p) == 0 || StringLen(cnt) == 0) { ArrayResize(lots, 0); return 0; }
         for(int c = 0; c < StringLen(cnt); c++)     // repeat count: digits only
         {
            ushort ch = StringGetCharacter(cnt, c);
            if(ch < '0' || ch > '9') { ArrayResize(lots, 0); return 0; }
         }
         rep = (int)StringToInteger(cnt);
         if(rep < 1) { ArrayResize(lots, 0); return 0; }
      }

      int dots = 0;                                  // lot: digits + at most one '.'
      for(int c = 0; c < StringLen(p); c++)
      {
         ushort ch = StringGetCharacter(p, c);
         if(ch == '.') { dots++; if(dots > 1) { ArrayResize(lots, 0); return 0; } }
         else if(ch < '0' || ch > '9') { ArrayResize(lots, 0); return 0; }
      }
      double v = StringToDouble(p);
      if(v <= 0) { ArrayResize(lots, 0); return 0; }

      int k = ArraySize(lots);
      if(k + rep > BD_MAX_LOT_STEPS) { ArrayResize(lots, 0); return 0; }
      ArrayResize(lots, k + rep);
      for(int r = 0; r < rep; r++) lots[k + r] = v;
   }
   return ArraySize(lots);
}

//--- FIX-5 (14.2.1, rev 14.2.2): PURE volume-constraint check ---------
//    Returns -1 when every step is tradable as written, else the 1-based
//    index of the first offending step ('why' explains). Since 14.2.2
//    (quyet dinh Chu nha) this is a HEADS-UP only: OnInit logs a warning,
//    the EA keeps running, Grid_NormalizeVolume applies min/step/max at
//    trade time (below-min -> broker MIN LOT) and ExecutionLayer logs
//    every adjusted order for tracking (AU-14-07 closed this way).
int Grid_ValidateVolumes(const double &lots[], const double vMin, const double vMax,
                         const double vStep, string &why)
{
   for(int i = 0; i < ArraySize(lots); i++)
   {
      double lot = lots[i];
      if(lot < vMin)
      { why = DoubleToString(lot, 3) + " < VOLUME_MIN " + DoubleToString(vMin, 3); return i + 1; }
      if(lot > vMax)
      { why = DoubleToString(lot, 3) + " > VOLUME_MAX " + DoubleToString(vMax, 3); return i + 1; }
      if(vStep > 0 && MathAbs(lot / vStep - MathRound(lot / vStep)) > 1e-6)
      { why = DoubleToString(lot, 3) + " is not a multiple of VOLUME_STEP " + DoubleToString(vStep, 3); return i + 1; }
   }
   return -1;
}

//--- FE-407 (v14.7): manual DCA distance chain in PIP -----------------
//    Chain "10x3-15x2-20" (same parser/syntax as the lot chain): gap #1..3
//    = 10 pip, #4..5 = 15 pip, #6+ = 20 pip (last repeats). Gap index for
//    the order being opened = count-1 (count = OPEN orders — Chu nha's
//    counting rule, an Overlap trim steps the index back). Unit: 1 pip =
//    BD_POINTS_PER_PIP reference points (FE-201: 10 pip = 1.00 USD on
//    gold, standard pip on 5-digit FX); Cfg.PointScale applies at the
//    usage site exactly like the classic formula.
int Grid_ChainDistancePoints(const int count, const double &gapsPip[])
{
   int n = ArraySize(gapsPip);
   if(n == 0 || count < 1) return 0;
   int idx = count - 1;
   if(idx > n - 1) idx = n - 1;
   return (int)MathRound(gapsPip[idx] * BD_POINTS_PER_PIP);
}

//--- FE-407: distance provider for the Strategy (classic OR manual) ---
class CDistancePlan
{
private:
   double m_gapsPip[];    // empty -> classic v13 formula
public:
   void InitClassic()                 { ArrayResize(m_gapsPip, 0); }
   bool InitManual(const string seq)  { return Grid_ParseLotSequence(seq, m_gapsPip) > 0; }
   int  Size() const                  { return ArraySize(m_gapsPip); }

   int DistancePoints(const int count) const
   {
      if(ArraySize(m_gapsPip) == 0)   // [STRATEGY-BEHAVIOR] classic path untouched
         return Grid_DistancePoints(count, Fix_Distance, Order_dinamic_distance,
                                    Dynamic_distance_start, Distance_multiplier);
      return Grid_ChainDistancePoints(count, m_gapsPip);
   }
};

//--- FE-408 (v14.7): THEORETICAL lot from a multiplier chain ----------
//    Chain "1.03x3-1.3x4-1.25-1.5": multiplications #1..3 use 1.03 (orders
//    #2..#4), next 4 use 1.3, then 1.25, then 1.5 repeats. Closed-form from
//    the base lot (Chu nha's decision): lot(#count+1) = base x PRODUCT of
//    the first `count` chain factors — NO intermediate rounding, so small
//    factors never get stuck at broker lot grain; rounding happens ONCE at
//    send time (Grid_NormalizeVolume + FIX-5 rev tracking log). MaxLot caps.
double Grid_ChainLot(const double baseLot, const int count, const double &mult[],
                     const double maxLot)
{
   double lot = baseLot;
   int n = ArraySize(mult);
   if(n > 0)
      for(int k = 0; k < count; k++)
         lot *= mult[k > n - 1 ? n - 1 : k];
   if(lot > maxLot) lot = maxLot;
   return lot;
}

//--- Default ILotSizer implementation --------------------------------
class CMartingaleSizer : public ILotSizer
{
public:
   double FirstLot(void)
   {
      return Grid_FirstLot(Cfg.LotInit, Cfg.Autolot, Cfg.Autolotsize,
                           AccountInfoDouble(ACCOUNT_MARGIN_FREE), Cfg.MaxLot);
   }
   double NextLot(const BasketSide &side)
   {
      if(side.count <= 0) return FirstLot();
      return Grid_MartingaleLot(side.pos[0].lots, side.count, Cfg.Martin, Cfg.MaxLot);
   }
};

//--- v14.1/14.2 FE-202+FE-301: ILotSizer from an explicit lot sequence
//    Order index counts OPEN positions (side.count) — the SAME rule as the
//    v13 martingale sizer, confirmed by Chu nha 2026-07-26: after an
//    Overlap trim (9 open -> 7) the next order is order #8 and takes
//    step 8 of the chain; the comment "|n" carries the same number.
//    Beyond the last step its lot repeats until the whole basket closes
//    (new cycle restarts at step 1 automatically since count returns 0).
//    Autolot is ignored while a sequence is active; MaxLot still caps.
class CSequenceSizer : public ILotSizer
{
private:
   double m_lots[];
public:
   bool Init(const string seq) { return Grid_ParseLotSequence(seq, m_lots) > 0; }
   int  Size() const           { return ArraySize(m_lots); }

   //--- FIX-5: fail-fast check against the CURRENT symbol's volume limits
   int ValidateVolumes(string &why) const
   {
      return Grid_ValidateVolumes(m_lots,
                                  SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN),
                                  SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX),
                                  SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP), why);
   }

   double FirstLot(void)
   {
      double lot = m_lots[0];
      if(lot > Cfg.MaxLot) lot = Cfg.MaxLot;
      return lot;
   }
   double NextLot(const BasketSide &side)
   {
      if(side.count <= 0) return FirstLot();
      int idx  = side.count;                  // order #count+1 -> zero-based idx = count
      int last = ArraySize(m_lots) - 1;
      if(idx > last) idx = last;              // beyond sequence: repeat last lot
      double lot = m_lots[idx];
      if(lot > Cfg.MaxLot) lot = Cfg.MaxLot;
      return lot;
   }
};
//--- FE-408: ILotSizer from a multiplier chain ------------------------
//    Base lot = actual first order of the basket (pos[0].lots — same base
//    the v13 martingale uses); first order of a series = FirstLot()
//    (Lot_Init / autolot, unchanged).
class CChainSizer : public ILotSizer
{
private:
   double m_mult[];
public:
   bool Init(const string seq) { return Grid_ParseLotSequence(seq, m_mult) > 0; }
   int  Size() const           { return ArraySize(m_mult); }

   double FirstLot(void)
   {
      return Grid_FirstLot(Cfg.LotInit, Cfg.Autolot, Cfg.Autolotsize,
                           AccountInfoDouble(ACCOUNT_MARGIN_FREE), Cfg.MaxLot);
   }
   double NextLot(const BasketSide &side)
   {
      if(side.count <= 0) return FirstLot();
      return Grid_ChainLot(side.pos[0].lots, side.count, m_mult, Cfg.MaxLot);
   }
};
#endif // BD_GRIDENGINE_MQH
