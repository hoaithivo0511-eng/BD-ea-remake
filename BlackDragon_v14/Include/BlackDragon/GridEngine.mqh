//+------------------------------------------------------------------+
//| GridEngine.mqh — BlackDragon v14.9.0                             |
//| Purpose   : DCA lot/distance chains + volume normalization.      |
//| Invariants: No orders. Chain indexing follows OPEN positions.    |
//| Depends on: Config.mqh, Types.mqh                                |
//| v14.9.0  : classic Martin/dynamic-distance runtime paths retired;|
//|             every active chain repeats its final value.          |
//+------------------------------------------------------------------+
#ifndef BD_GRIDENGINE_MQH
#define BD_GRIDENGINE_MQH
#include "Types.mqh"

//--- Regression oracles only -----------------------------------------
//    These two pure functions preserve the retired v13 formulas solely so
//    the existing test script can compare historical behavior. No EA input,
//    sizer, distance plan or OnInit branch calls them in v14.9 production.
int Grid_DistancePoints(const int count,
                        const int fixDistance,
                        const int dynStartOrder,
                        const int dynStartDistance,
                        const double multiplier)
{
   if(count < dynStartOrder - 1) return fixDistance;
   return (int)NormalizeDouble(dynStartDistance * MathPow(multiplier, count + 1 - dynStartOrder), 0);
}

double Grid_MartingaleLot(const double firstLot, const int count,
                          const double martin, const double maxLot)
{
   double lot = NormalizeDouble(firstLot * MathPow(martin, count), 2);
   if(lot > maxLot) lot = maxLot;
   return lot;
}

//--- First lot: Lot_Init, or FreeMargin/Autolotsize*0.01 when Autolot
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

//--- Shared positive chain parser -------------------------------------
//    Parse "0.01-0.02-0.04" or "0.01x5-0.02x3-0.05" -> flat values[].
//    Used by absolute-lot, multiplier and distance chains. '-' separates
//    steps; optional xN/XN repeats a step. Spaces are ignored. Returns 0
//    for invalid/empty input or expansion beyond BD_MAX_LOT_STEPS.
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
         for(int c = 0; c < StringLen(cnt); c++)
         {
            ushort ch = StringGetCharacter(cnt, c);
            if(ch < '0' || ch > '9') { ArrayResize(lots, 0); return 0; }
         }
         rep = (int)StringToInteger(cnt);
         if(rep < 1) { ArrayResize(lots, 0); return 0; }
      }

      int dots = 0;
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
//    Returns -1 when every explicit lot step is tradable as written, else
//    the first offending 1-based step. Runtime still normalizes the order;
//    the caller may surface this once because it changes actual risk/volume.
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

//--- Distance chain in PIP -------------------------------------------
//    "10x3-15x2-20" -> gaps 10,10,10,15,15,20,20,20... . Once the
//    explicit chain ends, its FINAL distance repeats for every later DCA.
//    Gap index for the order being opened = count-1, where count is OPEN
//    positions; Overlap trimming therefore steps the chain index back too.
int Grid_ChainDistancePoints(const int count, const double &gapsPip[])
{
   int n = ArraySize(gapsPip);
   if(n == 0 || count < 1) return 0;
   int idx = count - 1;
   if(idx > n - 1) idx = n - 1;
   return (int)MathRound(gapsPip[idx] * BD_POINTS_PER_PIP);
}

class CDistancePlan
{
private:
   double m_gapsPip[];
public:
   bool Init(const string seq) { return Grid_ParseLotSequence(seq, m_gapsPip) > 0; }
   int  Size() const           { return ArraySize(m_gapsPip); }

   int DistancePoints(const int count) const
   {
      return Grid_ChainDistancePoints(count, m_gapsPip);
   }
};

//--- Multiplier chain --------------------------------------------------
//    "1.03x3-1.3x4-1.25-1.5": multiplications #1..3 use 1.03, next 4
//    use 1.3, then 1.25, then 1.5 repeats forever. Closed-form from the
//    basket's first lot; no intermediate rounding. MaxLot caps theoretical
//    volume and broker normalization happens once when the order is sent.
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

//--- Absolute lot chain -----------------------------------------------
//    Order index counts OPEN positions. Beyond the last explicit step its
//    final lot repeats until the basket closes. Autolot is ignored in this
//    mode; MaxLot remains a hard theoretical cap.
class CSequenceSizer : public ILotSizer
{
private:
   double m_lots[];
public:
   bool Init(const string seq) { return Grid_ParseLotSequence(seq, m_lots) > 0; }
   int  Size() const           { return ArraySize(m_lots); }

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
      int idx  = side.count;
      int last = ArraySize(m_lots) - 1;
      if(idx > last) idx = last;
      double lot = m_lots[idx];
      if(lot > Cfg.MaxLot) lot = Cfg.MaxLot;
      return lot;
   }
};

//--- Multiplier-chain lot sizer ---------------------------------------
//    First order uses Lot_Init/Autolot. Later orders multiply from the
//    ACTUAL first position lot. Beyond the last factor, the final factor
//    repeats for every later DCA; Overlap trimming steps the index back.
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