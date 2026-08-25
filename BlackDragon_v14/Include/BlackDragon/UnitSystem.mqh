//+------------------------------------------------------------------+
//| UnitSystem.mqh — canonical price/pip/tick conversion policy      |
//| Invariants: pure helpers only; no symbol lookup or trade calls.  |
//+------------------------------------------------------------------+
#ifndef BD_UNIT_SYSTEM_MQH
#define BD_UNIT_SYSTEM_MQH

#ifndef BD_POINTS_PER_PIP
#define BD_POINTS_PER_PIP 10
#endif

enum eUnitSystemMode
{
   unit_LEGACY_COMPAT = 0, // Giữ nguyên nghĩa point chuẩn của file .set cũ
   unit_PIP_UNIFIED   = 1  // Mọi input khoảng cách chung được hiểu là pip
};

struct SUnitProfile
{
   bool   isGold;
   int    digits;
   double point;
   double tickSize;
   double pipSize;
   double legacyPointSize;
};

int Unit_LegacyPointScalePure(const bool isGold, const double point,
                              const bool autoGoldPip)
{
   if(!autoGoldPip || !isGold || point <= 0.0) return 1;
   int scale = (int)MathRound(0.01 / point);
   return scale < 1 ? 1 : scale;
}

double Unit_PipSizePure(const bool isGold, const double point, const int digits)
{
   if(point <= 0.0) return 0.0;
   if(isGold) return 0.10;
   return (digits == 3 || digits == 5) ? point * 10.0 : point;
}

double Unit_LegacyPointSizePure(const bool isGold, const double point,
                                const bool autoGoldPip)
{
   if(point <= 0.0) return 0.0;
   return point * (double)Unit_LegacyPointScalePure(isGold, point, autoGoldPip);
}

bool Unit_BuildProfilePure(const bool isGold, const double point, const int digits,
                           const double tickSize, const bool autoGoldPip,
                           SUnitProfile &out, string &why)
{
   why = "";
   out.isGold = isGold;
   out.digits = digits;
   out.point = point;
   out.tickSize = tickSize;
   out.pipSize = Unit_PipSizePure(isGold, point, digits);
   out.legacyPointSize = Unit_LegacyPointSizePure(isGold, point, autoGoldPip);
   if(point <= 0.0) { why = "SYMBOL_POINT <= 0"; return false; }
   if(tickSize <= 0.0) { why = "SYMBOL_TRADE_TICK_SIZE <= 0"; return false; }
   if(out.pipSize <= 0.0) { why = "derived pip size <= 0"; return false; }
   if(out.legacyPointSize <= 0.0) { why = "derived legacy point size <= 0"; return false; }
   return true;
}

double Unit_ConfigDistancePricePure(const double value,
                                    const eUnitSystemMode mode,
                                    const double legacyPointSize,
                                    const double pipSize)
{
   return value * (mode == unit_PIP_UNIFIED ? pipSize : legacyPointSize);
}

double Unit_DcaDistancePricePure(const double pips,
                                 const eUnitSystemMode mode,
                                 const double legacyPointSize,
                                 const double pipSize)
{
   double unitPrice = mode == unit_PIP_UNIFIED
      ? pipSize : legacyPointSize * (double)BD_POINTS_PER_PIP;
   return pips * unitPrice;
}

double Unit_PipsToPricePure(const double pips, const double pipSize)
{
   return pips * pipSize;
}

long Unit_PriceToTicksPure(const double price, const double tickSize)
{
   if(tickSize <= 0.0) return 0;
   return (long)MathRound(price / tickSize);
}

ulong Unit_PriceToBrokerPointsCeilPure(const double price, const double point)
{
   if(price <= 0.0 || point <= 0.0) return 0;
   return (ulong)MathCeil(price / point - 1e-9);
}

double Unit_CostShiftPricePure(const double costMoney, const double totalLots,
                               const double tickValue, const double tickSize)
{
   if(totalLots <= 0.0 || tickValue <= 0.0 || tickSize <= 0.0) return 0.0;
   return costMoney / (tickValue * totalLots) * tickSize;
}

string Unit_ModeName(const eUnitSystemMode mode)
{
   return mode == unit_PIP_UNIFIED ? "PIP_UNIFIED" : "LEGACY_COMPAT";
}

#endif // BD_UNIT_SYSTEM_MQH
