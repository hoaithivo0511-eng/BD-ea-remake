//+------------------------------------------------------------------+
//| BlackDragon.mq5 — EA Black Dragon v14.8.0 (modular rebuild)      |
//| Event handlers + module registration ONLY. All logic lives in    |
//| MQL5/Include/BlackDragon/. Read ARCHITECTURE.md before editing.  |
//+------------------------------------------------------------------+
#property copyright "Original strategy: Copyright 2026, Ramil Minniakhmetov. Modular rebuild v14."
#property version   "14.80"

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

CRsiStochSignal  g_sigBD;
CWmfSignal       g_sigWMF;
ISignal         *g_signal = NULL;
CBasketManager   g_basket;
CExecutionLayer  g_exec;
CMartingaleSizer g_sizer;
CSequenceSizer   g_seqSizer;
CChainSizer      g_chainSizer;
CDistancePlan    g_distPlan;
CNewsCalendar    g_news;
CMoneyGuard      g_guard;
CTimeSchedule    g_schedule;
CMobileControl   g_mobile;
CPanel           g_panel;
CStrategy        g_strategy;
CAdxFilter      *g_adx = NULL;
datetime         g_lastSavedHalt = 0;

int OnInit()
{
   Config_Init();

   Config_ApplyPointScale(Sym_PointScale());
   if(Sym_IsGold())
      Log_Info("Init", "Gold detected (" + (string)_Digits + " digits): PointScale=" +
               (string)Cfg.PointScale + " — 200 input points = 2.00 USD = 20 pips on any broker" +
               (AutoGoldPip ? "" : " (AutoGoldPip=OFF: scale forced 1)"));

   Persist_Load();

   ILotSizer *sizer = &g_sizer;
   if(LotMode_ == lot_Sequence)
   {
      if(!g_seqSizer.Init(LotSequence_))
      {
         Log_Error("Init", "LotMode=Sequence but LotSequence_ invalid: '" + LotSequence_ +
                   "' — expected e.g. 0.01-0.02-0.04 or 0.01x5-0.02x3-0.05");
         return INIT_PARAMETERS_INCORRECT;
      }
      string why = "";
      int bad = g_seqSizer.ValidateVolumes(why);
      if(bad > 0)
         Log_Warn("Init", "seqvol", "LotSequence_ step #" + (string)bad + " outside " + _Symbol +
                  " volume limits (" + why + ") — it will be adjusted at trade time and logged per order");
      sizer = &g_seqSizer;
      Log_Info("Init", "Manual lot sequence active: " + (string)g_seqSizer.Size() +
               " steps (xN expanded); beyond the last step its lot repeats; Autolot ignored. " +
               "Order index counts OPEN orders — an Overlap trim steps the index back");
   }
   else if(LotMode_ == lot_MultiplierChain)
   {
      if(!g_chainSizer.Init(MartinSequence_))
      {
         Log_Error("Init", "LotMode=Multiplier chain but MartinSequence_ invalid: '" + MartinSequence_ +
                   "' — expected e.g. 1.03x3-1.3x4-1.25-1.5");
         return INIT_PARAMETERS_INCORRECT;
      }
      sizer = &g_chainSizer;
      Log_Info("Init", "Multiplier chain active: " + (string)g_chainSizer.Size() +
               " steps (xN expanded); beyond the last step its factor repeats; " +
               "index counts OPEN orders (overlap trims step back)");
   }
   else if(StringLen(LotSequence_) > 0)
      Log_Info("Init", "LotSequence_ is set but LotMode=xLot multiplier — sequence ignored");

   if(DistanceMode_ == dist_Manual)
   {
      if(!g_distPlan.InitManual(DistanceSequence_))
      {
         Log_Error("Init", "DistanceMode=Manual but DistanceSequence_ invalid: '" + DistanceSequence_ +
                   "' — expected pip chain e.g. 10x3-15x2-20");
         return INIT_PARAMETERS_INCORRECT;
      }
      Log_Info("Init", "Manual distance chain active: " + (string)g_distPlan.Size() +
               " gaps (pip; 1 pip = " + (string)BD_POINTS_PER_PIP + " ref points, PointScale applies); " +
               "beyond the last gap it repeats; index counts OPEN orders");
   }
   else
      g_distPlan.InitClassic();

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
   g_guard.Init();
   g_basket.SeedDayProfit();
   g_panel.Init();
   g_strategy.Init(&g_basket, &g_exec, sizer, &g_guard, &g_distPlan);

   g_strategy.AddNewSeriesFilter(new CHaltFilter(&g_guard));
   g_strategy.AddGridFilter(new CHaltFilter(&g_guard));

   // v14.8.0: detailed TimeLocal HH:MM windows are the only time filter.
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

   if(UseAdxFilter)
   {
      g_adx = new CAdxFilter();
      if(g_adx.Init()) g_strategy.AddNewSeriesFilter(g_adx);
      else
      {
         delete g_adx;
         g_adx = NULL;
         Log_Error("Init", "ADX filter init failed — running without it");
      }
   }

   g_lastSavedHalt = Cfg.HaltUntil;
   EventSetMillisecondTimer(BD_PANEL_TIMER_MS);
   Log_Info("Init", "EA Black Dragon v" + BD_VERSION + " started. ExecMode=" +
            (ExecMode == exec_Async ? "Async" : "Sync"));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   Persist_Save();
   g_strategy.Deinit();
   g_sigBD.Deinit();
   g_sigWMF.Deinit();
   g_panel.Deinit(reason);
}

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
   if(ctx.barTime == 0) return false;
   ctx.newsAllowsNew = g_news.AllowsNewOrders(ctx.now);
   ctx.signalBuy    = false;
   ctx.signalSell   = false;
   return true;
}

void OnTick()
{
   EAContext ctx;
   if(!BuildContext(ctx)) return;
   g_signal.Compute(ctx);

   if(SignalSource_ == sig_WMF && ShowWmfSignals)
   {
      SWmfMark marks[];
      int nMarks = g_sigWMF.TakePendingMarks(marks);
      for(int i = 0; i < nMarks; i++)
         g_panel.MarkWmfSignal(marks[i].isBuy, marks[i].time, marks[i].price);
   }

   g_basket.Update(ctx);
   g_strategy.OnTick(ctx, g_panel);
}

void OnTimer()
{
   g_news.Refresh();
   g_exec.Watchdog();
   if(UseMobileControl && !MQLInfoInteger(MQL_TESTER))
      if(g_mobile.Scan(&g_exec))
      {
         g_panel.RedrawButtons();
         Persist_Save();
      }
   g_basket.CheckDayRollover(TimeCurrent());
   g_panel.ShowHalt(g_guard.HaltUntil(TimeCurrent()));

   if(Cfg.HaltUntil != g_lastSavedHalt)
   {
      g_lastSavedHalt = Cfg.HaltUntil;
      Persist_Save();
   }

   g_panel.DrawLevels(g_basket.buy, g_basket.sell);
   g_panel.Refresh(g_basket.buy.totalProfit, g_basket.sell.totalProfit, g_basket.DayProfit());
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   g_exec.OnTransaction(trans, request, result);
   if(trans.type == TRADE_TRANSACTION_POSITION && trans.symbol == _Symbol)
      g_basket.Invalidate();
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD && trans.symbol == _Symbol)
   {
      g_basket.Invalidate();
      if(HistoryDealSelect(trans.deal))
         if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) == _Symbol &&
            Basket_OwnsMagic(HistoryDealGetInteger(trans.deal, DEAL_MAGIC), Magic, flag_Hand_Ord) &&
            HistoryDealGetInteger(trans.deal, DEAL_ENTRY) == DEAL_ENTRY_OUT)
            g_basket.OnDealClosed(HistoryDealGetDouble(trans.deal, DEAL_PROFIT),
                                  HistoryDealGetDouble(trans.deal, DEAL_SWAP),
                                  HistoryDealGetDouble(trans.deal, DEAL_COMMISSION));
   }
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   g_panel.OnEvent(id, lparam, dparam, sparam);
}
