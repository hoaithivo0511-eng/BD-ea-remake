//+------------------------------------------------------------------+
//| BlackDragon.mq5 — EA Black Dragon v15.01 / T17.24 remediation candidate |
//| Event handlers + module registration ONLY.                       |
//+------------------------------------------------------------------+
#property copyright "Original strategy: Copyright 2026, Ramil Minniakhmetov. Modular rebuild v14/T17."
#property version   "15.01"

#include <BlackDragon/Config.mqh>
#include <BlackDragon/Recovery/RecoveryTypes.mqh>
#include <BlackDragon/Pyramid/PyramidAnchorT177.mqh>
// C2 compatibility: while RecoveryT16Config is parsed, route Pyramid semantic
// text through the T17.7 wrapper. DYNAMIC returns the exact legacy string;
// FIRST_CORE adds its explicit semantic revision to persistence identity.
#define Pyramid_SemanticText Pyramid_T177ExtendedSemanticText
#include <BlackDragon/Recovery/RecoveryEngine.mqh>
#undef Pyramid_SemanticText
// T17.13 wrappers retain T17.6/T17.7 bases and only relax read-only Core-growth admission.
#include <BlackDragon/Pyramid/CorePyramidT1713.mqh>
#include <BlackDragon/Recovery/RecoveryDcaT1713.mqh>
#include <BlackDragon/Recovery/RecoveryExitCoordinator.mqh>
#include <BlackDragon/Types.mqh>
#include <BlackDragon/Logger.mqh>
#include <BlackDragon/License.mqh>
#include <BlackDragon/SignalEngine.mqh>
#include <BlackDragon/WmfSignal.mqh>
#include <BlackDragon/WmfSignalOverlay.mqh>
#include <BlackDragon/GridEngine.mqh>
#include <BlackDragon/EntryFilters.mqh>
#include <BlackDragon/NewsCalendar.mqh>
#include <BlackDragon/BasketManager.mqh>
#include <BlackDragon/ExitEngine.mqh>
#include <BlackDragon/ExecutionLayer.mqh>
#include <BlackDragon/MoneyGuard.mqh>
#include <BlackDragon/MobileControl.mqh>
#include <BlackDragon/Persistence.mqh>
#include <BlackDragon/StrategyT1713.mqh>
#include <BlackDragon/Filters/AdxFilter.mqh>
#include <BlackDragon/Pyramid/PyramidProtection.mqh>

CRsiStochSignal  g_sigBD;
CWmfSignal       g_sigWMF;
CWmfSignalOverlay g_wmfOverlay;
ISignal         *g_signal = NULL;
CBasketManager   g_basket;
CExecutionLayer  g_exec;
CRecoveryEngine  g_recovery;
CRecoveryExitCoordinator g_recoveryExit;
CCorePyramidEngine g_pyramid;
CPyramidProtection g_pyProtection;
CSequenceSizer   g_seqSizer;
CChainSizer      g_chainSizer;
CDistancePlan    g_distPlan;
CNewsCalendar    g_news;
CMoneyGuard      g_guard;
CTimeSchedule    g_schedule;
CMobileControl   g_mobile;
CStrategy        g_strategy;
CAdxFilter      *g_adx = NULL;
datetime         g_lastSavedHalt = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   Config_Init();

   string recoveryWhy = "";
   if(!Recovery_ValidateCompleteConfig((long)Magic,
                                       AccountInfoInteger(ACCOUNT_MARGIN_MODE),
                                       recoveryWhy))
   {
      Log_Error("Init", "Recovery complete config invalid: " + recoveryWhy);
      return INIT_PARAMETERS_INCORRECT;
   }

   bool anyLossStopEnabled=SL_>0.0 || MoneySLAllAccount<0.0 ||
                           MoneySLAll<0.0 || MoneySLBuy<0.0 ||
                           MoneySLSell<0.0 || DailySLMoney<0.0 ||
                           DailySLPercent<0.0 || EnableGlobalHedgeSL_;
   if(Recovery_T1716UnsafeGrowthEnvelopePure(
         RecoveryMode_,ContinueDcaAfterHedge_,CorePyramidMode_,
         PyramidMaxAdds_,MaxOrdersBuy,MaxOrdersSell,
         PyramidMaxTotalLots_,PyramidRiskBudgetPercent_,
         anyLossStopEnabled))
      Log_Warn("Init","t1716unsafe",
               "CẢNH BÁO T17.16: Recovery tiếp tục DCA + Pyramid tái kích hoạt "
               "đang dùng toàn bộ side cap, không lot/risk budget và không SL; "
               "đây là cấu hình stress có nguy cơ cạn margin");

   string unitWhy = "";
   if(!Config_BindUnitProfile(Sym_IsGold(), _Point, _Digits,
                              SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE), unitWhy))
   {
      Log_Error("Init", "Unit profile invalid: " + unitWhy);
      return INIT_PARAMETERS_INCORRECT;
   }
   Log_Info("Init", "UnitSystem=" + Unit_ModeName(Cfg.UnitMode) +
            "; point=" + DoubleToString(Cfg.Point, _Digits) +
            "; pip=" + DoubleToString(Cfg.PipSize, _Digits) +
            "; tick=" + DoubleToString(Cfg.TickSize, _Digits) +
            (Cfg.UnitMode == unit_PIP_UNIFIED && !AutoGoldPip
             ? "; AutoGoldPip ignored in unified mode" : ""));

   if(!g_pyProtection.Init(&g_basket,&g_exec,&g_recovery)) return INIT_PARAMETERS_INCORRECT;
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
   g_wmfOverlay.Init();
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
      else
      {
         delete g_adx;
         g_adx = NULL;
         Log_Error("Init", "T17.23 ADX filter enabled nhưng init thất bại — fail closed");
         return INIT_FAILED;
      }
   }

   g_lastSavedHalt = Cfg.HaltUntil;

   EventSetMillisecondTimer(BD_SERVICE_TIMER_MS);
   Log_Info("Init", "EA Black Dragon T17.22 Core PY protection build started. ExecMode=" +
            (ExecMode == exec_Async ? "Async" : "Sync") +
            "; CorePyramid=" + (string)(int)CorePyramidMode_ +
            "; CoreAnchor=" + Pyramid_T177AnchorModeName(CorePyramidAnchorMode_) +
            "; HedgePyramid=" + (string)(int)HedgePyramidMode_);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   g_pyProtection.ReportPerformance();
#ifdef BD_LOCAL_DIAGNOSTICS
   Print("T17.24 observation scans=",g_bdObservationBook.Scans(),
         " visits=",g_bdObservationBook.Visits()," aggregate hits=",g_bdObservationBook.Hits());
#endif
   g_recovery.FlushPersistence();
   Persist_Save();
   g_strategy.Deinit();
   g_sigBD.Deinit();
   g_sigWMF.Deinit();
   g_wmfOverlay.Deinit(reason);
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

   if(SignalSource_ == sig_WMF && g_wmfOverlay.Enabled())
   {
      SWmfMark marks[];
      int nMarks = g_sigWMF.TakePendingMarks(marks);
      for(int i = 0; i < nMarks; i++)
         g_wmfOverlay.Mark(marks[i].isBuy, marks[i].time, marks[i].price);
   }

   g_basket.Update(ctx);
   g_pyProtection.Observe(ctx);
   if(RecoveryMode_!=recovery_OFF)
      g_bdObservationBook.Begin(_Symbol,(long)Magic,(long)RecoveryMagic_,SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP));
   g_recovery.OnTick(ctx);
   g_bdObservationBook.End(); // all mutation paths below continue to read live state
   g_strategy.OnTick(ctx);
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
         Persist_Save();
   g_basket.CheckDayRollover(TimeCurrent());

   if(Cfg.HaltUntil != g_lastSavedHalt)
   {
      g_lastSavedHalt = Cfg.HaltUntil;
      Persist_Save();
   }
}

//+------------------------------------------------------------------+
bool IsT1722TopologyTransaction(const MqlTradeTransaction &trans)
{
   if(PyramidSLMode_==py_protect_OFF || trans.symbol!=_Symbol) return false;
   return trans.type==TRADE_TRANSACTION_DEAL_ADD ||
          trans.type==TRADE_TRANSACTION_DEAL_UPDATE ||
          trans.type==TRADE_TRANSACTION_DEAL_DELETE ||
          trans.type==TRADE_TRANSACTION_POSITION;
}

//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   bool pyTopology=IsT1722TopologyTransaction(trans);
   if(pyTopology || trans.type==TRADE_TRANSACTION_DEAL_ADD ||
      trans.type==TRADE_TRANSACTION_DEAL_UPDATE || trans.type==TRADE_TRANSACTION_DEAL_DELETE)
   {
      g_pyramidDealRevision++;
      g_basket.Invalidate();
   }
   if(trans.type==TRADE_TRANSACTION_DEAL_UPDATE || trans.type==TRADE_TRANSACTION_DEAL_DELETE)
   {
      g_basket.InvalidateDayCash();
      Recovery_T165InvalidateGuardCash();
      g_basket.Invalidate();
   }
   g_exec.OnTransaction(trans, request, result);
   if(pyTopology)
      g_pyProtection.OnTransaction(trans);
   bool suppressRecoveryDeal = g_recoveryExit.OnTradeTransaction(trans);
   if(!suppressRecoveryDeal)
      g_recovery.OnTradeTransaction(trans);
   else if(trans.type == TRADE_TRANSACTION_DEAL_ADD && trans.deal != 0)
   {
      g_recovery.RecordDealCursor(trans.deal);
      g_recovery.FlushPersistence();
      // Exit coordination suppresses strategy replay, not realized cash.
      // The normal engine observer is skipped in this branch.
      Recovery_T165GuardObserveDeal(trans.deal,TimeCurrent());
   }
   if(trans.type == TRADE_TRANSACTION_POSITION && trans.symbol == _Symbol)
      g_basket.Invalidate();
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD && trans.deal!=0)
   {
      g_basket.Invalidate();
      // Exact symbol/date/position ownership is resolved by the shared ledger.
      // A missing deal invalidates the cash proof and is retried on later ticks.
      g_basket.OnDealCash(trans.deal,0,0,0,0);
   }

}

//+------------------------------------------------------------------+
