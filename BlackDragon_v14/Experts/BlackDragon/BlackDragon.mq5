//+------------------------------------------------------------------+
//| BlackDragon.mq5 — EA Black Dragon T17 Full Pyramid test build    |
//| Event handlers + module registration ONLY.                       |
//+------------------------------------------------------------------+
#property copyright "Original strategy: Copyright 2026, Ramil Minniakhmetov. Modular rebuild v14/T17."
#property version   "15.00"

#include <BlackDragon/Config.mqh>
#include <BlackDragon/Recovery/RecoveryTypes.mqh>
#include <BlackDragon/Recovery/RecoveryEngine.mqh>
#include <BlackDragon/Recovery/RecoveryDca.mqh>
#include <BlackDragon/Recovery/RecoveryExitCoordinator.mqh>
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
CRecoveryEngine  g_recovery;
CRecoveryExitCoordinator g_recoveryExit;
CCorePyramidEngine g_pyramid;
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

//+------------------------------------------------------------------+
int OnInit()
{
   Config_Init();

   string recoveryWhy = "";
   if(!Recovery_ValidateFoundation(RecoveryMode_, (long)Magic, RecoveryMagic_,
                                   RecoveryStartAfterDca_,
                                   AccountInfoInteger(ACCOUNT_MARGIN_MODE),
                                   recoveryWhy))
   {
      Log_Error("Init", "Recovery foundation invalid: " + recoveryWhy);
      return INIT_PARAMETERS_INCORRECT;
   }
   if(!Recovery_ValidateShadowConfig(RecoveryMode_, HedgeGapPips_, recoveryWhy))
   {
      Log_Error("Init", "Recovery shadow config invalid: " + recoveryWhy);
      return INIT_PARAMETERS_INCORRECT;
   }
   if(!Recovery_ValidateDcaConfig(RecoveryMode_, MinHedgeCoveragePercent_,
                                  TargetRecoveryCorridorPips_, recoveryWhy))
   {
      Log_Error("Init", "Recovery DCA/corridor config invalid: " + recoveryWhy);
      return INIT_PARAMETERS_INCORRECT;
   }
   // T17.6: this gate is deliberately top-level. Recovery OFF bypasses the
   // T16 engine validator, but a staged Hedge Pyramid with Recovery OFF is a
   // silent no-op and must fail configuration instead of misleading the user.
   if(!Recovery_T17ValidateCrossInputs(recoveryWhy))
   {
      Log_Error("Init", "Recovery/Pyramid cross-input config invalid: " + recoveryWhy);
      return INIT_PARAMETERS_INCORRECT;
   }

   Config_ApplyPointScale(Sym_PointScale());
   if(Sym_IsGold())
      Log_Info("Init", "Gold detected (" + (string)_Digits + " digits): PointScale=" +
               (string)Cfg.PointScale + " — 200 input points = 2.00 USD = 20 pips on any broker" +
               (AutoGoldPip ? "" : " (AutoGoldPip=OFF: scale forced 1)"));

   if(!g_recovery.Init()) return INIT_PARAMETERS_INCORRECT;

   Persist_Load();

   ILotSizer *sizer = NULL;
   if(LotMode_ == lot_Sequence)
   {
      if(!g_seqSizer.Init(LotSequence_))
      {
         Log_Error("Init", "LotSequence_ invalid: '" + LotSequence_ +
                   "' — expected e.g. 0.01-0.02-0.04 or 0.01x5-0.02x3-0.05");
         return INIT_PARAMETERS_INCORRECT;
      }
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

   if(!g_distPlan.Init(DistanceSequence_))
   {
      Log_Error("Init", "DistanceSequence_ invalid: '" + DistanceSequence_ +
                "' — expected e.g. 20x5-24-28.8-34.6-41.5");
      return INIT_PARAMETERS_INCORRECT;
   }

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

   string pyramidWhy = "";
   if(!g_pyramid.Init(&g_exec, pyramidWhy))
   {
      Log_Error("Init", "T17 Pyramid config/init invalid: " + pyramidWhy);
      return INIT_PARAMETERS_INCORRECT;
   }

   if(RecoveryMode_ == recovery_ACTIVE)
   {
      string startupWhy = "";
      if(!g_recovery.StartupReconcile(g_exec, startupWhy))
         Log_Error("Recovery", "ACTIVE startup is FAIL-CLOSED: " + startupWhy);
   }
   g_recoveryExit.Init(&g_recovery, &g_exec);
   g_news.Init();
   g_guard.Init();
   g_basket.SeedDayProfit();
   g_panel.Init();
   g_strategy.Init(&g_basket, &g_exec, sizer, &g_guard, &g_distPlan,
                   &g_recovery, &g_recoveryExit, &g_pyramid);

   g_strategy.AddNewSeriesFilter(new CRecoveryStartupFilter(&g_recovery));
   g_strategy.AddNewSeriesFilter(new CHaltFilter(&g_guard));
   g_strategy.AddGridFilter(new CHaltFilter(&g_guard));
   g_strategy.AddGridFilter(new CRecoveryDcaFilter(&g_recovery, &g_basket));

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
      else { delete g_adx; g_adx = NULL; Log_Error("Init", "ADX filter init failed — running without it"); }
   }

   g_lastSavedHalt = Cfg.HaltUntil;

   EventSetMillisecondTimer(BD_PANEL_TIMER_MS);
   Log_Info("Init", "EA Black Dragon T17 Pyramid test build started. ExecMode=" +
            (ExecMode == exec_Async ? "Async" : "Sync") +
            "; CorePyramid=" + (string)(int)CorePyramidMode_ +
            "; HedgePyramid=" + (string)(int)HedgePyramidMode_);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   g_recovery.FlushPersistence();
   Persist_Save();
   g_strategy.Deinit();
   g_sigBD.Deinit();
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
   if(ctx.barTime == 0) return false;
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
   g_signal.Compute(ctx);

   if(SignalSource_ == sig_WMF && ShowWmfSignals)
   {
      SWmfMark marks[];
      int nMarks = g_sigWMF.TakePendingMarks(marks);
      for(int i = 0; i < nMarks; i++)
         g_panel.MarkWmfSignal(marks[i].isBuy, marks[i].time, marks[i].price);
   }

   g_basket.Update(ctx);
   g_recovery.OnTick(ctx);
   g_strategy.OnTick(ctx, g_panel);
}

//+------------------------------------------------------------------+
void OnTimer()
{
   g_news.Refresh();
   g_exec.Watchdog();
   g_recovery.FlushPersistence();
   string exitWhy = "";
   if(g_recoveryExit.Drive(TimeCurrent(), exitWhy) && exitWhy != "")
      Log_Warn("Recovery", "exitcoordtimer", "T8 exit coordination: " + exitWhy);
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

//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   g_exec.OnTransaction(trans, request, result);
   bool suppressRecoveryDeal = g_recoveryExit.OnTradeTransaction(trans);
   if(!suppressRecoveryDeal)
      g_recovery.OnTradeTransaction(trans);
   else if(trans.type == TRADE_TRANSACTION_DEAL_ADD && trans.deal != 0)
   {
      g_recovery.RecordDealCursor(trans.deal);
      g_recovery.FlushPersistence();
   }
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

//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   g_panel.OnEvent(id, lparam, dparam, sparam);
}
//+------------------------------------------------------------------+
