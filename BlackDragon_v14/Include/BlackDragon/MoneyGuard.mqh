//+------------------------------------------------------------------+
//| MoneyGuard.mqh — BlackDragon v14.3.0                             |
//| Purpose   : FE-401/402 (theo CCBSN manual, Chu nha duyet plan    |
//|             26/07/2026): money TP/SL theo scope account/magic/   |
//|             side, %-difference close-all, daily profit target    |
//|             voi trading halt + delay dau ngay moi.               |
//| Invariants: READ-ONLY consumer cua BasketManager va AccountInfo. |
//|             KHONG BAO GIO gui lenh — chi tra quyet dinh, Strategy|
//|             thuc thi qua ExecutionLayer.                         |
//| Quyet dinh Chu nha: daily scope = Magic cua bot; hedged-TP kich  |
//|             hoat khi CA HAI ro cung mo; panel bypass khi halt.   |
//| Depends on: Config.mqh, Types.mqh, Logger.mqh                    |
//+------------------------------------------------------------------+
#ifndef BD_MONEYGUARD_MQH
#define BD_MONEYGUARD_MQH
#include "Types.mqh"
#include "Logger.mqh"

enum eGuardAction
{
   GUARD_NONE = 0,
   GUARD_CLOSE_ACCOUNT,      // close EVERY position on the account (any magic/symbol)
   GUARD_CLOSE_MAGIC,        // close both baskets of this EA
   GUARD_CLOSE_BUY,          // close buy basket only
   GUARD_CLOSE_SELL,         // close sell basket only
   GUARD_CLOSE_MAGIC_DAILY   // close both baskets AND halt until next day + delay
};

//--- PURE decision helpers (unit-tested in RunTests + offline suite) --
//    Convention (per manual): TP thresholds POSITIVE (500), SL thresholds
//    NEGATIVE (-500), 0 = feature off.
bool MG_MoneyTpHit(const double profit, const double tp)
{ return tp > 0 && profit >= tp; }

bool MG_MoneySlHit(const double profit, const double sl)
{ return sl < 0 && profit <= sl; }

//--- CCBSN formula: (loi nhuan chieu loi) + (loi nhuan chieu lo x (1+%)) >= 0.
//    Doc example: Buy +10, Sell -8, 2% -> 10 + (-8*1.02) = +1.84 -> close.
//    Only meaningful when one side is losing; both-positive is Money TP All's job.
bool MG_PctDiffHit(const double buyProfit, const double sellProfit, const double pct)
{
   if(pct <= 0) return false;
   double win  = MathMax(buyProfit, sellProfit);
   double lose = MathMin(buyProfit, sellProfit);
   if(lose >= 0) return false;
   return win + lose * (1.0 + pct / 100.0) >= 0;
}

//--- FE-402: daily net (floating + realized today) vs $ and % thresholds.
//    dayStartBalance <= 0 disables the % checks (no valid base).
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

class CMoneyGuard
{
private:
   datetime m_haltUntil;      // 0 = not halted
   //--- validated copies of the inputs (wrong sign -> warn + OFF, 14.2.2 spirit)
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
      datetime dayStart = StringToTime(TimeToString(now, TIME_DATE));   // 00:00 server time today
      m_haltUntil = dayStart + 86400 + NewDayDelayMin * 60;
      Log_Info("Guard", "DAILY target/limit hit — closing baskets, trading halted until " +
               TimeToString(m_haltUntil, TIME_DATE | TIME_MINUTES) +
               " (new day + " + (string)NewDayDelayMin + "min delay)");
   }

public:
   CMoneyGuard() : m_haltUntil(0) {}

   void Init()
   {
      m_haltUntil = 0;
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
      if(any) Log_Info("Guard", "MoneyGuard active (FE-401/402) — thresholds armed");
   }

   bool     Halted(const datetime now) const { return m_haltUntil != 0 && now < m_haltUntil; }
   datetime HaltUntil(const datetime now) const { return Halted(now) ? m_haltUntil : 0; }

   //--- Evaluate once per tick. Widest scope wins. Repeat-fire while the
   //    condition persists is harmless: closes are idempotent (sync: gone
   //    next tick; async: HasPendingClose guards) and daily re-fire is
   //    blocked by Halted(). Trigger logs are throttled (60s) by Logger.
   eGuardAction Check(const datetime now, const double buyProfit, const double sellProfit,
                      const bool bothOpen, const double dayNet, const double dayStartBalance)
   {
      if(m_haltUntil != 0 && now >= m_haltUntil)
      {
         m_haltUntil = 0;
         Log_Info("Guard", "daily halt over — trading resumed");
      }

      double magicNet = buyProfit + sellProfit;
      double accNet   = AccountInfoDouble(ACCOUNT_PROFIT);   // floating, whole account

      // 1. account-wide money TP/SL (widest scope)
      if(MG_MoneyTpHit(accNet, m_tpAccount))
      { Log_Warn("Guard", "tpacc", "Money TP All account: " + DoubleToString(accNet, 2) + " >= " + DoubleToString(m_tpAccount, 2)); return GUARD_CLOSE_ACCOUNT; }
      if(MG_MoneySlHit(accNet, m_slAccount))
      { Log_Warn("Guard", "slacc", "Money SL All account: " + DoubleToString(accNet, 2) + " <= " + DoubleToString(m_slAccount, 2)); return GUARD_CLOSE_ACCOUNT; }

      // 2. daily target/limit (magic scope) -> close + halt
      if(!Halted(now) &&
         (MG_DailyTpHit(dayNet, m_dailyTpM, dayStartBalance, m_dailyTpP) ||
          MG_DailySlHit(dayNet, m_dailySlM, dayStartBalance, m_dailySlP)))
      {
         Log_Warn("Guard", "daily", "Daily net " + DoubleToString(dayNet, 2) + " (start balance " +
                  DoubleToString(dayStartBalance, 2) + ") hit the daily target/limit");
         StartHalt(now);
         return GUARD_CLOSE_MAGIC_DAILY;
      }

      // 3. magic-wide: hedged special TP first (both baskets open), then normal
      if(bothOpen && MG_MoneyTpHit(magicNet, m_tpHedged))
      { Log_Warn("Guard", "tphdg", "Money TP All (hedged, both sides open): " + DoubleToString(magicNet, 2) + " >= " + DoubleToString(m_tpHedged, 2)); return GUARD_CLOSE_MAGIC; }
      if(MG_MoneyTpHit(magicNet, m_tpAll))
      { Log_Warn("Guard", "tpall", "Money TP All: " + DoubleToString(magicNet, 2) + " >= " + DoubleToString(m_tpAll, 2)); return GUARD_CLOSE_MAGIC; }
      if(MG_MoneySlHit(magicNet, m_slAll))
      { Log_Warn("Guard", "slall", "Money SL All: " + DoubleToString(magicNet, 2) + " <= " + DoubleToString(m_slAll, 2)); return GUARD_CLOSE_MAGIC; }

      // 4. %-difference close-all (CCBSN formula)
      if(bothOpen && MG_PctDiffHit(buyProfit, sellProfit, m_pctDiff))
      { Log_Warn("Guard", "pctd", "PctDiff close-all: buy " + DoubleToString(buyProfit, 2) + " / sell " + DoubleToString(sellProfit, 2) + " @ " + DoubleToString(m_pctDiff, 2) + "%"); return GUARD_CLOSE_MAGIC; }

      // 5. per-side money TP/SL
      if(MG_MoneyTpHit(buyProfit, m_tpBuy))
      { Log_Warn("Guard", "tpbuy", "Money TP Buy: " + DoubleToString(buyProfit, 2)); return GUARD_CLOSE_BUY; }
      if(MG_MoneySlHit(buyProfit, m_slBuy))
      { Log_Warn("Guard", "slbuy", "Money SL Buy: " + DoubleToString(buyProfit, 2)); return GUARD_CLOSE_BUY; }
      if(MG_MoneyTpHit(sellProfit, m_tpSell))
      { Log_Warn("Guard", "tpsel", "Money TP Sell: " + DoubleToString(sellProfit, 2)); return GUARD_CLOSE_SELL; }
      if(MG_MoneySlHit(sellProfit, m_slSell))
      { Log_Warn("Guard", "slsel", "Money SL Sell: " + DoubleToString(sellProfit, 2)); return GUARD_CLOSE_SELL; }

      return GUARD_NONE;
   }
};

//--- FE-402: entry filter — blocks AUTOMATED entries while daily-halted.
//    Registered on BOTH chains (new series + grid adds) in OnInit.
//    Panel manual orders stay bypassed (Chu nha's decision, v13 philosophy).
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
