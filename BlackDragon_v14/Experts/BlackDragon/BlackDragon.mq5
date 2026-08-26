//+------------------------------------------------------------------+
//| BlackDragon.mq5 — EA Black Dragon v14.9.0 (modular rebuild)      |
//| Event handlers + module registration ONLY. All logic lives in    |
//| MQL5/Include/BlackDragon/. Read ARCHITECTURE.md before editing.  |
//+------------------------------------------------------------------+
#property copyright "Original strategy: Copyright 2026, Ramil Minniakhmetov. Modular rebuild v14."
#property version   "14.90"

#include <BlackDragon/Config.mqh>
#include <BlackDragon/Types.mqh>
#include <BlackDragon/Logger.mqh>
#include <BlackDragon/License.mqh>
#include <BlackDragon/SignalEngine.mqh>
#include <BlackDragon/WmfSignal.mqh>
#include <BlackDragon/GridEngine.mqh>
#include <BlackDragon/EntryFilters.mqh>
#include <BlackDragon/NewsCalendar.mqh>
#include <BlackDragon/BasketManager.mqh>
#include <BlackDragon/ExitEngine.mqh>
#include <BlackDragon/ExecutionLayer.mqh>
#include <BlackDragon/MoneyGuard.mqh>
#include <BlackDragon/MobileControl.mqh>
#include <BlackDragon/Panel.mqh>
#include <BlackDragon/Persistence.mqh>
#include <BlackDragon/Strategy.mqh>
#include <BlackDragon/Filters/AdxFilter.mqh>

CRsiStochSignal  g_sigBD;      // FE-405: BD RSI signal (v13)
CWmfSignal       g_sigWMF;     // FE-405: WMF signal (TradingView port)
ISignal         *g_signal = NULL;
CBasketManager   g_basket;
CExecutionLayer  g_exec;
CSequenceSizer   g_seqSizer;    // explicit DCA lot sequence
CChainSizer      g_chainSizer;  // DCA multiplier chain
CDistancePlan    g_distPlan;    // DCA pip-distance chain
CNewsCalendar    g_news;
CMoneyGuard      g_guard;       // FE-401/402 (v14.3)
CTimeSchedule    g_schedule;    // FE-403 (v14.4)
CMobileControl   g_mobile;      // FE-404 (v14.5)
CPanel           g_panel;
CStrategy        g_strategy;
CAdxFilter      *g_adx = NULL;
datetime         g_lastSavedHalt = 0;   // BD-R4 (v14.7.2): last Cfg.HaltUntil written to the state file

//+------------------------------------------------------------------+
int OnInit()
{
   Config_Init();

   //--- FE-201: gold pip convention (1 USD = 10 pips). Reference quote is
   //    2-digit gold; on a 3-digit broker every point-based input is x10.
   Config_ApplyPointScale(Sym_PointScale());
   if(Sym_IsGold())
      Log_Info("Init", "Gold detected (" + (string)_Digits + " digits): PointScale=" +
               (string)Cfg.PointScale + " — 200 input points = 2.00 USD = 20 pips on any broker" +
               (AutoGoldPip ? "" : " (AutoGoldPip=OFF: scale forced 1)"));

   Persist_Load();                       // restore panel toggles after restart

   //--- v14.9: only two DCA-lot models remain. Numeric values 1/2 are kept
   //    stable so existing sequence-based .set files do not change meaning.
   ILotSizer *sizer = NULL;
   if(LotMode_ == lot_Sequence)
   {
      if(!g_seqSizer.Init(LotSequence_))
      {
         Log_Error("Init", "LotSequence_ invalid: '" + LotSequence_ +
                   "' — expected e.g. 0.01-0.02-0.04 or 0.01x5-0.02x3-0.05");
         return INIT_PARAMETERS_INCORRECT;
      }
      // Explicit lots outside the broker grid are still surfaced once because
      // runtime normalization changes the actual requested risk/volume.
      string why = "";
      int bad = g_seqSizer.ValidateVolumes(why);
      if(bad > 0)
         Log_Warn("Init", "seqvol", "LotSequence_ step #" + (string)bad + " outside " + _Symbol +
                  " volume limits (" + why + ") — it will be adjusted at trade time");
      sizer = &g_seqSizer;
   }
   else if(LotMode_ == lot_MultiplierChain)
   {
      if(!g_chainSizer.Init(MartinSequence_))
      {
         Log_Error("Init", "MartinSequence_ invalid: '" + MartinSequence_ +
                   "' — expected e.g. 1.5 or 1.03x3-1.3x4-1.25-1.5");
         return INIT_PARAMETERS_INCORRECT;
      }
      sizer = &g_chainSizer;
   }
   else
   {
      Log_Error("Init", "LotMode_ retired/invalid — use 1=Lot sequence or 2=Multiplier chain");
      return INIT_PARAMETERS_INCORRECT;
   }

   //--- v14.9: one distance model only. A valid pip chain is mandatory.
   //    If MaxOrders exceeds the explicit chain, Grid_ChainDistancePoints()
   //    silently repeats the final distance for every later DCA by design.
   if(!g_distPlan.Init(DistanceSequence_))
   {
      Log_Error("Init", "DistanceSequence_ invalid: '" + DistanceSequence_ +
                "' — expected e.g. 20x5-24-28.8-34.6-41.5");
      return INIT_PARAMETERS_INCORRECT;
   }

   //--- FE-405 (v14.6): choose the entry-signal source. Only the chosen
   //    implementation is initialised (its indicator handles created).
   if(SignalSource_ == sig_WMF)
   {
      if(!g_sigWMF.Init()) return INIT_FAILED;
      g_signal = &g_sigWMF;
      Log_Info("Init", "Signal source: WMF " + (WmfMode == wmf_Cross ? "Cross" : "Trend") +
               " (len " + (string)WmfLength + ", x" + DoubleToString(WmfFactor, 2) +
               ", EMA " + (string)WmfEmaLength + ")" + (Use_Stoh ? " + Stoch filter" : ""));
   }
   else
   {
      if(!g_sigBD.Init()) return INIT_FAILED;
      g_signal = &g_sigBD;
   }
   g_exec.Init();
   g_news.Init();
   g_guard.Init();                       // FE-401/402: validate thresholds (wrong sign -> warn + off)
   g_basket.SeedDayProfit();             // also snapshots day-start balance (FE-402)
   g_panel.Init();
   g_strategy.Init(&g_basket, &g_exec, sizer, &g_guard, &g_distPlan);

   //--- FE-402: daily halt blocks AUTOMATED entries on BOTH chains
   //    (panel manual orders stay bypassed — Chu nha's decision)
   g_strategy.AddNewSeriesFilter(new CHaltFilter(&g_guard));
   g_strategy.AddGridFilter(new CHaltFilter(&g_guard));

   //--- FE-403 / v14.8.0: the detailed PC/local HH:MM schedule is now
   //    the only time-window filter (legacy Start_Hour/End_Hour removed).
   if(UseTimeLimit)
   {
      string terr = "";
      if(!g_schedule.Init(terr))
      {
         Log_Error("Init", "Time limit config invalid: " + terr + " — expected HH:MM, e.g. 07:00");
         return INIT_PARAMETERS_INCORRECT;
      }
      g_strategy.AddNewSeriesFilter(new CTimeFilter(&g_schedule, false));
      g_strategy.AddGridFilter(new CTimeFilter(&g_schedule, true));
      Log_Info("Init", "Time limit active (PC/local time): " + g_schedule.Describe() +
               (DcaOutsideTime ? " — DCA allowed outside windows" : "") +
               (MQLInfoInteger(MQL_TESTER) ? " [tester: local time = modelled server time]" : ""));
   }

   //--- P5 extension registration (everything enabled is visible here)
   if(UseAdxFilter)
   {
      g_adx = new CAdxFilter();
      if(g_adx.Init()) g_strategy.AddNewSeriesFilter(g_adx);
      else { delete g_adx; g_adx = NULL; Log_Error("Init", "ADX filter init failed — running without it"); }
   }

   //--- BD-R4 (v14.7.2): seed the halt-persistence watermark AFTER
   //    Persist_Load() + g_guard.Init() so a restored deadline is not
   //    immediately rewritten by the first timer tick.
   g_lastSavedHalt = Cfg.HaltUntil;

   EventSetMillisecondTimer(BD_PANEL_TIMER_MS);   // C3: UI + housekeeping cadence
   Log_Info("Init", "EA Black Dragon v" + BD_VERSION + " started. ExecMode=" +
            (ExecMode == exec_Async ? "Async" : "Sync"));
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   Persist_Save();
   g_strategy.Deinit();   // deletes registered filters (incl. g_adx)
   g_sigBD.Deinit();      // FE-405: both are guard-safe on unopened handles
   g_sigWMF.Deinit();
   g_panel.Deinit(reason);
}

//+------------------------------------------------------------------+
bool BuildContext(EAContext &ctx)
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return false;
   ctx.ask          = tick.ask;
   ctx.bid          = tick.bid;
   ctx.point        = _Point;
   ctx.digits       = _Digits;
   ctx.spreadPoints = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   ctx.now          = TimeCurrent();
   ctx.barTime      = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(ctx.barTime == 0) return false;   // AU-14-08: history not synchronized yet
   ctx.newsAllowsNew = g_news.AllowsNewOrders(ctx.now);
   ctx.signalBuy    = false;
   ctx.signalSell   = false;
   return true;
}

//+------------------------------------------------------------------+
void OnTick()
{
   EAContext ctx;
   if(!BuildContext(ctx)) return;
   g_signal.Compute(ctx);       // once per bar internally

   //--- FE-406 (14.6.1): draw WMF BUY/SELL arrows (seed history + live)
   if(SignalSource_ == sig_WMF && ShowWmfSignals)
   {
      SWmfMark marks[];
      int nMarks = g_sigWMF.TakePendingMarks(marks);
      for(int i = 0; i < nMarks; i++)
         g_panel.MarkWmfSignal(marks[i].isBuy, marks[i].time, marks[i].price);
   }

   g_basket.Update(ctx);        // rebuild only when invalidated (C1)
   g_strategy.OnTick(ctx, g_panel);
   //--- BD-R8 (v14.7.2): g_panel.DrawLevels() moved to OnTimer. ARCHITECTURE
   //    rule C3 puts UI redraws on the 500ms timer, not on the tick stream;
   //    on a busy gold feed this was 8 ObjectMove/ObjectCreate calls per tick
   //    with no visual benefit. The LEVELS themselves are still recomputed
   //    every tick by g_basket.Update() — only the redraw is throttled.
}

//+------------------------------------------------------------------+
void OnTimer()
{
   g_news.Refresh();            // hourly cache; never blocks OnTick (Nhom D)
   g_exec.Watchdog();           // async journal reconciliation (Nhom B)
   //--- FE-404 (v14.5): mobile-control pendings (skip in tester — no user)
   if(UseMobileControl && !MQLInfoInteger(MQL_TESTER))
      if(g_mobile.Scan(&g_exec))
      {
         g_panel.RedrawButtons();   // reflect remote flag changes on the panel
         Persist_Save();            // remote state survives restart
      }
   g_basket.CheckDayRollover(TimeCurrent());
   g_panel.ShowHalt(g_guard.HaltUntil(TimeCurrent()));   // FE-402: halt notice in title

   //--- BD-R4 (v14.7.2): persist the daily-halt deadline on TRANSITIONS only
   //    (halt armed / halt expired). At most two extra writes per day, versus
   //    twice a second if this ran unconditionally. Without it, a terminal
   //    restart after a daily SL resumed trading on the same day.
   if(Cfg.HaltUntil != g_lastSavedHalt)
   {
      g_lastSavedHalt = Cfg.HaltUntil;
      Persist_Save();
   }

   g_panel.DrawLevels(g_basket.buy, g_basket.sell);   // BD-R8: moved off OnTick (C3 cadence)
   g_panel.Refresh(g_basket.buy.totalProfit, g_basket.sell.totalProfit, g_basket.DayProfit());
}

//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   g_exec.OnTransaction(trans, request, result);      // confirm async journal
   if(trans.type == TRADE_TRANSACTION_POSITION && trans.symbol == _Symbol)
      g_basket.Invalidate();                          // audit fix: SL/TP modify has no DEAL_ADD
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD && trans.symbol == _Symbol)
   {
      g_basket.Invalidate();                          // event-driven rebuild (C1)
      //--- BD-R6 (v14.7.2, quyet dinh Chu nha 11/08/2026): Basket_OwnsMagic()
      //    is the SAME rule the position scan and SeedDayProfit() use. With
      //    flag_Hand_Ord ON, a manual magic-0 order's floating P/L already fed
      //    the daily net, so its realized P/L must be booked here too —
      //    otherwise dayNet fell back the instant a winning manual order
      //    closed. flag_Hand_Ord OFF (default): unchanged, Magic only.
      if(HistoryDealSelect(trans.deal))
         if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) == _Symbol &&
            Basket_OwnsMagic(HistoryDealGetInteger(trans.deal, DEAL_MAGIC), Magic, flag_Hand_Ord) &&
            HistoryDealGetInteger(trans.deal, DEAL_ENTRY) == DEAL_ENTRY_OUT)
            g_basket.OnDealClosed(HistoryDealGetDouble(trans.deal, DEAL_PROFIT),
                                  HistoryDealGetDouble(trans.deal, DEAL_SWAP),
                                  HistoryDealGetDouble(trans.deal, DEAL_COMMISSION));  // C2
   }
}

//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   g_panel.OnEvent(id, lparam, dparam, sparam);   // requests are consumed on next tick
}
//+------------------------------------------------------------------+