//+------------------------------------------------------------------+
//| MoneyGuard.mqh — BlackDragon T17.4                              |
//| Purpose   : FE-401/402 money TP/SL decisions. Absolute-money     |
//|             guards use CURRENT floating P/L and outrank strategy.|
//| Invariants: READ-ONLY consumer; NEVER sends trade requests.      |
//+------------------------------------------------------------------+
#ifndef BD_MONEYGUARD_MQH
#define BD_MONEYGUARD_MQH
#include "Types.mqh"
#include "Logger.mqh"

enum eGuardAction
{
   GUARD_NONE = 0,
   GUARD_CLOSE_ACCOUNT,
   GUARD_CLOSE_MAGIC,
   GUARD_CLOSE_BUY,
   GUARD_CLOSE_SELL,
   GUARD_CLOSE_MAGIC_DAILY
};

bool MG_MoneyTpHit(const double profit, const double tp)
{ return tp > 0 && profit >= tp; }

bool MG_MoneySlHit(const double profit, const double sl)
{ return sl < 0 && profit <= sl; }

bool MG_PctDiffHit(const double buyProfit, const double sellProfit, const double pct)
{
   if(pct <= 0) return false;
   double win  = MathMax(buyProfit, sellProfit);
   double lose = MathMin(buyProfit, sellProfit);
   if(lose >= 0) return false;
   return win + lose * (1.0 + pct / 100.0) >= 0;
}

// T17.4: the PctDiff ratio remains a current-floating signal. Its secondary
// close-to-flat surplus gate must additionally repay active Pyramid campaign
// realized debt. Missing campaign history defers only PctDiff fail-closed.
bool MG_PctDiffEconomicHitBuffered(const double buyProfit,
                                   const double sellProfit,
                                   const double pct,
                                   const double pyramidCampaignRealizedCash,
                                   const bool campaignHistoryValid,
                                   const double executionBufferCash)
{
   if(!campaignHistoryValid || !MG_PctDiffHit(buyProfit, sellProfit, pct)) return false;
   double buffer = MathMax(executionBufferCash, 0.0);
   return buyProfit + sellProfit + pyramidCampaignRealizedCash + 1e-9 >= buffer;
}

// Compatibility wrapper for callers/tests that have no active campaign debt.
bool MG_PctDiffHitBuffered(const double buyProfit, const double sellProfit,
                           const double pct, const double executionBufferCash)
{
   return MG_PctDiffEconomicHitBuffered(buyProfit, sellProfit, pct, 0.0, true,
                                        executionBufferCash);
}

// Conservative synchronous close reserve: two current spreads provide the
// execution/cost floor, then one configured deviation is reserved for every
// sequential close request. Invalid symbol economics fail closed.
double MG_PctDiffExecutionReserveCashPure(const double spreadPrice,
                                          const double deviationPrice,
                                          const double totalLots,
                                          const int closeRequestCount,
                                          const double tickSize,
                                          const double tickValue)
{
   if(tickSize <= 0.0 || tickValue <= 0.0) return DBL_MAX;
   if(totalLots <= 0.0) return 0.0;
   int requests = closeRequestCount > 0 ? closeRequestCount : 1;
   double spread = MathMax(spreadPrice, tickSize);
   double move = 2.0 * spread + MathMax(deviationPrice, 0.0) * requests;
   return move / tickSize * tickValue * totalLots;
}

// Pure latch transition used by Strategy: once a close is armed, a later
// price retreat cannot cancel it. Only broker-observable flat scope clears it.
eGuardAction MG_LatchNextPure(const eGuardAction latched,
                              const eGuardAction triggered,
                              const bool scopeFlat)
{
   if(latched != GUARD_NONE)
      return scopeFlat ? GUARD_NONE : latched;
   return triggered;
}

bool MG_DailyTpHit(const double dayNet, const double tpMoney,
                   const double dayStartBalance, const double tpPct)
{
   if(tpMoney > 0 && dayNet >= tpMoney) return true;
   if(tpPct > 0 && dayStartBalance > 0 && dayNet >= dayStartBalance * tpPct / 100.0) return true;
   return false;
}
bool MG_DailySlHit(const double dayNet, const double slMoney,
                   const double dayStartBalance, const double slPct)
{
   if(slMoney < 0 && dayNet <= slMoney) return true;
   if(slPct < 0 && dayStartBalance > 0 && dayNet <= dayStartBalance * slPct / 100.0) return true;
   return false;
}

datetime MG_HaltDeadline(const datetime dayStart, const int delayMin)
{
   int d = delayMin < 0 ? 0 : delayMin;
   return dayStart + 86400 + d * 60;
}

class CMoneyGuard
{
private:
   datetime m_haltUntil;
   double m_pctDiff;
   double m_tpAccount, m_slAccount;
   double m_tpAll, m_slAll, m_tpHedged;
   double m_tpBuy, m_slBuy, m_tpSell, m_slSell;
   double m_dailyTpM, m_dailySlM, m_dailyTpP, m_dailySlP;

   double TpIn(const double v, const string name)
   {
      if(v < 0) { Log_Warn("Guard", "sg" + name, name + "=" + DoubleToString(v, 2) + " must be POSITIVE — treated as OFF"); return 0; }
      return v;
   }
   double SlIn(const double v, const string name)
   {
      if(v > 0) { Log_Warn("Guard", "sg" + name, name + "=" + DoubleToString(v, 2) + " must be NEGATIVE — treated as OFF"); return 0; }
      return v;
   }

   void StartHalt(const datetime now)
   {
      datetime dayStart = StringToTime(TimeToString(now, TIME_DATE));
      m_haltUntil = MG_HaltDeadline(dayStart, NewDayDelayMin);
      Cfg.HaltUntil = m_haltUntil;
      Log_Info("Guard", "DAILY target/limit hit — closing baskets, trading halted until " +
               TimeToString(m_haltUntil, TIME_DATE | TIME_MINUTES) +
               " (new day + " + (string)NewDayDelayMin + "min delay)");
   }

public:
   CMoneyGuard() : m_haltUntil(0) {}

   void Init()
   {
      m_haltUntil = Cfg.HaltUntil;
      m_pctDiff   = TpIn(PctDiffClose,      "PctDiffClose");
      m_tpAccount = TpIn(MoneyTPAllAccount, "MoneyTPAllAccount");
      m_slAccount = SlIn(MoneySLAllAccount, "MoneySLAllAccount");
      m_tpAll     = TpIn(MoneyTPAll,        "MoneyTPAll");
      m_slAll     = SlIn(MoneySLAll,        "MoneySLAll");
      m_tpHedged  = TpIn(MoneyTPAllHedged,  "MoneyTPAllHedged");
      m_tpBuy     = TpIn(MoneyTPBuy,        "MoneyTPBuy");
      m_slBuy     = SlIn(MoneySLBuy,        "MoneySLBuy");
      m_tpSell    = TpIn(MoneyTPSell,       "MoneyTPSell");
      m_slSell    = SlIn(MoneySLSell,       "MoneySLSell");
      m_dailyTpM  = TpIn(DailyTPMoney,      "DailyTPMoney");
      m_dailySlM  = SlIn(DailySLMoney,      "DailySLMoney");
      m_dailyTpP  = TpIn(DailyTPPercent,    "DailyTPPercent");
      m_dailySlP  = SlIn(DailySLPercent,    "DailySLPercent");
      bool any = m_pctDiff > 0 || m_tpAccount > 0 || m_slAccount < 0 || m_tpAll > 0 || m_slAll < 0 ||
                 m_tpHedged > 0 || m_tpBuy > 0 || m_slBuy < 0 || m_tpSell > 0 || m_slSell < 0 ||
                 m_dailyTpM > 0 || m_dailySlM < 0 || m_dailyTpP > 0 || m_dailySlP < 0;
      if(any) Log_Info("Guard", "MoneyGuard active (FE-401/402) — T17.4 floating-money priority armed");
      if(Halted(TimeCurrent()))
         Log_Info("Guard", "daily halt RESTORED from state file — trading stays halted until " +
                  TimeToString(m_haltUntil, TIME_DATE | TIME_MINUTES));
   }

   bool     Halted(const datetime now) const { return m_haltUntil != 0 && now < m_haltUntil; }
   datetime HaltUntil(const datetime now) const { return Halted(now) ? m_haltUntil : 0; }

   // P0 T17.4: absolute-money rules operate only on CURRENT floating P/L.
   // No realized Pyramid/Recovery history is accepted here, so a previously
   // realized Peel loss can never postpone a configured floating-money exit.
   eGuardAction CheckFloatingPriority(const datetime now,
                                      const double buyFloating,
                                      const double sellFloating,
                                      const bool bothOpen,
                                      const double accountFloating)
   {
      if(m_haltUntil != 0 && now >= m_haltUntil)
      {
         m_haltUntil = 0;
         Cfg.HaltUntil = 0;
         Log_Info("Guard", "daily halt over — trading resumed");
      }

      double magicNet = buyFloating + sellFloating;

      if(MG_MoneyTpHit(accountFloating, m_tpAccount))
      { Log_Warn("Guard", "tpacc", "Money TP All account FLOATING: " + DoubleToString(accountFloating, 2) + " >= " + DoubleToString(m_tpAccount, 2)); return GUARD_CLOSE_ACCOUNT; }
      if(MG_MoneySlHit(accountFloating, m_slAccount))
      { Log_Warn("Guard", "slacc", "Money SL All account FLOATING: " + DoubleToString(accountFloating, 2) + " <= " + DoubleToString(m_slAccount, 2)); return GUARD_CLOSE_ACCOUNT; }

      if(bothOpen && MG_MoneyTpHit(magicNet, m_tpHedged))
      { Log_Warn("Guard", "tphdg", "Money TP All (hedged) FLOATING: " + DoubleToString(magicNet, 2) + " >= " + DoubleToString(m_tpHedged, 2)); return GUARD_CLOSE_MAGIC; }
      if(MG_MoneyTpHit(magicNet, m_tpAll))
      { Log_Warn("Guard", "tpall", "Money TP All FLOATING: " + DoubleToString(magicNet, 2) + " >= " + DoubleToString(m_tpAll, 2)); return GUARD_CLOSE_MAGIC; }
      if(MG_MoneySlHit(magicNet, m_slAll))
      { Log_Warn("Guard", "slall", "Money SL All FLOATING: " + DoubleToString(magicNet, 2) + " <= " + DoubleToString(m_slAll, 2)); return GUARD_CLOSE_MAGIC; }

      if(MG_MoneyTpHit(buyFloating, m_tpBuy))
      { Log_Warn("Guard", "tpbuy", "Money TP Buy FLOATING: " + DoubleToString(buyFloating, 2)); return GUARD_CLOSE_BUY; }
      if(MG_MoneySlHit(buyFloating, m_slBuy))
      { Log_Warn("Guard", "slbuy", "Money SL Buy FLOATING: " + DoubleToString(buyFloating, 2)); return GUARD_CLOSE_BUY; }
      if(MG_MoneyTpHit(sellFloating, m_tpSell))
      { Log_Warn("Guard", "tpsel", "Money TP Sell FLOATING: " + DoubleToString(sellFloating, 2)); return GUARD_CLOSE_SELL; }
      if(MG_MoneySlHit(sellFloating, m_slSell))
      { Log_Warn("Guard", "slsel", "Money SL Sell FLOATING: " + DoubleToString(sellFloating, 2)); return GUARD_CLOSE_SELL; }

      return GUARD_NONE;
   }

   // Secondary guards run only after the absolute-money priority pass.
   eGuardAction CheckSecondaryFloating(const datetime now,
                                       const double buyFloating,
                                       const double sellFloating,
                                       const bool bothOpen,
                                       const double dayNet,
                                       const double dayStartBalance,
                                       const bool dayNetValid,
                                       const double pyramidCampaignRealizedCash,
                                       const bool pctCampaignHistoryValid,
                                       const double pctDiffExecutionBufferCash)
   {
      if(dayNetValid && !Halted(now) &&
         (MG_DailyTpHit(dayNet, m_dailyTpM, dayStartBalance, m_dailyTpP) ||
          MG_DailySlHit(dayNet, m_dailySlM, dayStartBalance, m_dailySlP)))
      {
         Log_Warn("Guard", "daily", "Daily net " + DoubleToString(dayNet, 2) + " (start balance " +
                  DoubleToString(dayStartBalance, 2) + ") hit the daily target/limit");
         StartHalt(now);
         return GUARD_CLOSE_MAGIC_DAILY;
      }

      if(bothOpen && MG_PctDiffEconomicHitBuffered(buyFloating, sellFloating,
                                                   m_pctDiff,
                                                   pyramidCampaignRealizedCash,
                                                   pctCampaignHistoryValid,
                                                   pctDiffExecutionBufferCash))
      {
         Log_Warn("Guard", "pctd", "PctDiff close-all FLOATING: buy " +
                  DoubleToString(buyFloating, 2) + " / sell " +
                  DoubleToString(sellFloating, 2) + " @ " +
                  DoubleToString(m_pctDiff, 2) + "%; Pyramid campaign realized=" +
                  DoubleToString(pyramidCampaignRealizedCash, 2) +
                  "; execution reserve=" +
                  DoubleToString(MathMax(pctDiffExecutionBufferCash, 0.0), 2));
         return GUARD_CLOSE_MAGIC;
      }
      return GUARD_NONE;
   }

   // Compatibility API retained for pre-T17.3 test callers. Production
   // Strategy no longer uses this realized-aware path for absolute money TP/SL.
   eGuardAction CheckScopedEconomic(const datetime now,
                                    const double buyProfit, const double sellProfit,
                                    const bool bothOpen,
                                    const double dayNet, const double dayStartBalance,
                                    const bool dayNetValid,
                                    const double accountEconomicProfit,
                                    const bool economicProfitValid)
   {
      if(m_haltUntil != 0 && now >= m_haltUntil)
      {
         m_haltUntil = 0;
         Cfg.HaltUntil = 0;
      }

      double magicNet = buyProfit + sellProfit;
      double accNet   = economicProfitValid ? accountEconomicProfit
                                            : AccountInfoDouble(ACCOUNT_PROFIT);

      if(economicProfitValid && MG_MoneyTpHit(accNet, m_tpAccount)) return GUARD_CLOSE_ACCOUNT;
      if(MG_MoneySlHit(accNet, m_slAccount)) return GUARD_CLOSE_ACCOUNT;
      if(dayNetValid && !Halted(now) &&
         (MG_DailyTpHit(dayNet, m_dailyTpM, dayStartBalance, m_dailyTpP) ||
          MG_DailySlHit(dayNet, m_dailySlM, dayStartBalance, m_dailySlP)))
      { StartHalt(now); return GUARD_CLOSE_MAGIC_DAILY; }
      if(economicProfitValid && bothOpen && MG_MoneyTpHit(magicNet, m_tpHedged)) return GUARD_CLOSE_MAGIC;
      if(economicProfitValid && MG_MoneyTpHit(magicNet, m_tpAll)) return GUARD_CLOSE_MAGIC;
      if(MG_MoneySlHit(magicNet, m_slAll)) return GUARD_CLOSE_MAGIC;
      if(economicProfitValid && bothOpen && MG_PctDiffHit(buyProfit, sellProfit, m_pctDiff)) return GUARD_CLOSE_MAGIC;
      if(economicProfitValid && MG_MoneyTpHit(buyProfit, m_tpBuy)) return GUARD_CLOSE_BUY;
      if(MG_MoneySlHit(buyProfit, m_slBuy)) return GUARD_CLOSE_BUY;
      if(economicProfitValid && MG_MoneyTpHit(sellProfit, m_tpSell)) return GUARD_CLOSE_SELL;
      if(MG_MoneySlHit(sellProfit, m_slSell)) return GUARD_CLOSE_SELL;
      return GUARD_NONE;
   }

   eGuardAction CheckScoped(const datetime now,
                            const double buyProfit, const double sellProfit,
                            const bool bothOpen,
                            const double dayNet, const double dayStartBalance,
                            const bool dayNetValid)
   {
      return CheckScopedEconomic(now, buyProfit, sellProfit, bothOpen,
                                 dayNet, dayStartBalance, dayNetValid,
                                 AccountInfoDouble(ACCOUNT_PROFIT), true);
   }

   eGuardAction Check(const datetime now, const double buyProfit, const double sellProfit,
                      const bool bothOpen, const double dayNet, const double dayStartBalance)
   {
      return CheckScoped(now, buyProfit, sellProfit, bothOpen,
                         dayNet, dayStartBalance, true);
   }
};

class CHaltFilter : public IEntryFilter
{
private:
   CMoneyGuard *m_guard;
public:
   CHaltFilter(CMoneyGuard *guard) : m_guard(guard) {}
   bool Allow(const EAContext &ctx, const int dir)
   {
      return !m_guard.Halted(ctx.now);
   }
};
#endif // BD_MONEYGUARD_MQH
