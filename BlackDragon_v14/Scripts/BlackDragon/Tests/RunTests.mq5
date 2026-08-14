//+------------------------------------------------------------------+
//| Tests/RunTests.mq5 — BlackDragon v14.0.0 unit tests              |
//| Run as a Script on any chart. Asserts pure-function behavior:    |
//| grid distance, martingale lots, breakeven, trailing, overlap.    |
//| Every strategy formula change MUST keep these green (or update   |
//| them consciously with a CHANGELOG entry).                        |
//| v14.7.2: last section pins the BD-R1..R9 deep-review fixes.      |
//+------------------------------------------------------------------+
#property script_show_inputs
#include <BlackDragon/Config.mqh>
#include <BlackDragon/Types.mqh>
#include <BlackDragon/GridEngine.mqh>
#include <BlackDragon/ExitEngine.mqh>
#include <BlackDragon/BasketManager.mqh>
#include <BlackDragon/ExecutionLayer.mqh>   // v14.1: Exec_BuildComment
#include <BlackDragon/MoneyGuard.mqh>       // v14.3: MG_* pure functions
#include <BlackDragon/EntryFilters.mqh>     // v14.4: TL_* pure functions
#include <BlackDragon/MobileControl.mqh>    // v14.5: MC_* pure functions
#include <BlackDragon/WmfSignal.mqh>        // v14.6: WMF_* pure functions

int g_pass = 0;
int g_fail = 0;

void Check(const string name, const bool cond)
{
   if(cond) { g_pass++; return; }
   g_fail++;
   Print("FAIL: ", name);
}

void CheckEq(const string name, const double got, const double want, const double eps = 1e-9)
{
   if(MathAbs(got - want) <= eps) { g_pass++; return; }
   g_fail++;
   Print("FAIL: ", name, " got=", DoubleToString(got, 10), " want=", DoubleToString(want, 10));
}

void OnStart()
{
   //--- Grid distance (defaults: Fix 200, dyn from order 6, start 200, x1.2)
   // [STRATEGY-BEHAVIOR] v13 rule: count < 6-1 -> 200; else 200*1.2^(count+1-6)
   CheckEq("dist count=1 (fix zone)",     Grid_DistancePoints(1, 200, 6, 200, 1.2), 200);
   CheckEq("dist count=4 (fix zone)",     Grid_DistancePoints(4, 200, 6, 200, 1.2), 200);
   CheckEq("dist count=5 (dyn boundary)", Grid_DistancePoints(5, 200, 6, 200, 1.2), 200);   // 200*1.2^0
   CheckEq("dist count=6",                Grid_DistancePoints(6, 200, 6, 200, 1.2), 240);   // 200*1.2^1
   CheckEq("dist count=7",                Grid_DistancePoints(7, 200, 6, 200, 1.2), 288);   // 200*1.2^2
   CheckEq("dist count=9",                Grid_DistancePoints(9, 200, 6, 200, 1.2), 415);   // round(414.72)

   //--- Martingale lot (defaults: x1.5, MaxLot 5, 2 digits)
   CheckEq("lot n=0", Grid_MartingaleLot(0.01, 0, 1.5, 5), 0.01);
   CheckEq("lot n=2", Grid_MartingaleLot(0.01, 2, 1.5, 5), NormalizeDouble(0.01*MathPow(1.5,2),2));
   CheckEq("lot n=4", Grid_MartingaleLot(0.01, 4, 1.5, 5), 0.05);            // 0.050625 -> 0.05
   CheckEq("lot cap", Grid_MartingaleLot(0.01, 30, 1.5, 5), 5.0);            // MaxLot cap
   Check("lot monotonic", Grid_MartingaleLot(0.01, 6, 1.5, 5) > Grid_MartingaleLot(0.01, 5, 1.5, 5));

   //--- First lot / autolot
   CheckEq("first lot fixed",   Grid_FirstLot(0.01, false, 1000, 10000, 5), 0.01);
   CheckEq("first lot autolot", Grid_FirstLot(0.01, true, 1000, 10000, 5), 0.1);
   CheckEq("first lot capped",  Grid_FirstLot(0.01, true, 1000, 10000000, 5), 5.0);

   //--- Breakeven (fix #3: signed swap; fix #8: tickValue guard)
   // buy, avg 1.10000, 0.1 lot, swap -1$, tickValue 1, point 0.0001 -> BE above avg
   CheckEq("BE buy negative swap", Basket_Breakeven(1.10000, 0.1, -1.0, 1.0, 0.0001, true),  1.10100, 1e-8);
   // positive swap must LOWER the buy BE (v13 MathAbs bug raised it)
   CheckEq("BE buy positive swap", Basket_Breakeven(1.10000, 0.1, 1.0, 1.0, 0.0001, true),   1.09900, 1e-8);
   CheckEq("BE sell negative swap", Basket_Breakeven(1.10000, 0.1, -1.0, 1.0, 0.0001, false), 1.09900, 1e-8);
   CheckEq("BE tickValue guard",   Basket_Breakeven(1.10000, 0.1, -1.0, 0.0, 0.0001, true),  1.10000, 1e-8); // fix #8
   CheckEq("BE zero lots",         Basket_Breakeven(1.10000, 0.0, -1.0, 1.0, 0.0001, true),  0.0);

   //--- Virtual exits
   Check("TP buy hit",      Exit_VirtualTpHit(true, 1.2000, 1.2000, 1.2002));
   Check("TP buy not hit",  !Exit_VirtualTpHit(true, 1.2000, 1.1999, 1.2001));
   Check("TP off",          !Exit_VirtualTpHit(true, 0, 99, 99));
   Check("SL sell hit",     Exit_VirtualSlHit(false, 1.3000, 1.2999, 1.3001));

   //--- Trailing (fix #2: gap THROUGH the level still closes)
   Check("trail buy touch", Exit_TrailHit(true, true, 1.1000, 1.1000, 1.1002));
   Check("trail buy gap",   Exit_TrailHit(true, true, 1.1000, 1.0800, 1.0802)); // v13 missed this (100pt window)
   Check("trail not armed", !Exit_TrailHit(true, false, 1.1000, 1.0800, 1.0802));
   Check("trail sell gap",  Exit_TrailHit(false, true, 1.1000, 1.1200, 1.1202));

   //--- Overlap (fix #10: first order must be LOSING)
   Check("overlap fires",        Exit_OverlapHit(8, 8, true, -10.0, 10.30, 3));   // 10.3 >= 10.3
   Check("overlap below thresh", !Exit_OverlapHit(8, 8, true, -10.0, 10.29, 3));
   Check("overlap count low",    !Exit_OverlapHit(7, 8, true, -10.0, 20.0, 3));
   Check("overlap off",          !Exit_OverlapHit(8, 8, false, -10.0, 20.0, 3));
   Check("overlap first profitable blocked", !Exit_OverlapHit(8, 8, true, 5.0, 20.0, 3)); // fix #10

   //--- v14.1 FE-201: gold pip scale (1 USD = 10 pips; ref = 2-digit quote)
   CheckEq("scale gold 2-digit", Sym_PointScalePure(true, 0.01),    1);
   CheckEq("scale gold 3-digit", Sym_PointScalePure(true, 0.001),   10);
   CheckEq("scale non-gold",     Sym_PointScalePure(false, 0.00001), 1);
   CheckEq("scale zero-point guard", Sym_PointScalePure(true, 0),   1);

   //--- v14.1 FE-202: lot sequence parse
   double seq[];
   CheckEq("seq parse count",     Grid_ParseLotSequence("0.01-0.02-0.04", seq), 3);
   CheckEq("seq parse v0",        seq[0], 0.01);
   CheckEq("seq parse v2",        seq[2], 0.04);
   CheckEq("seq parse spaces",    Grid_ParseLotSequence(" 0.01 - 0.02 ", seq), 2);
   CheckEq("seq parse single",    Grid_ParseLotSequence("0.05", seq), 1);
   CheckEq("seq invalid token",   Grid_ParseLotSequence("0.01-abc", seq), 0);
   CheckEq("seq invalid empty part", Grid_ParseLotSequence("0.01--0.02", seq), 0);
   CheckEq("seq invalid leading sep", Grid_ParseLotSequence("-0.01-0.02", seq), 0);
   CheckEq("seq empty",           Grid_ParseLotSequence("", seq), 0);

   //--- v14.1 FE-202: sequence sizer indexing (Cfg.MaxLot from defaults)
   Config_Init();
   CSequenceSizer sz;
   Check("sizer init ok",         sz.Init("0.01-0.02-0.04"));
   CheckEq("sizer order1 (first)", sz.FirstLot(), 0.01);
   BasketSide bs;
   bs.count = 0; CheckEq("sizer count0 -> first", sz.NextLot(bs), 0.01);
   bs.count = 1; CheckEq("sizer order2",          sz.NextLot(bs), 0.02);
   bs.count = 2; CheckEq("sizer order3",          sz.NextLot(bs), 0.04);
   bs.count = 5; CheckEq("sizer beyond -> last",  sz.NextLot(bs), 0.04);
   Check("sizer rejects garbage", !sz.Init("0.01-x"));

   //--- v14.2 FE-301: xN expansion "0.01x5-0.02x3-0.05" -> 9 flat steps
   CheckEq("seqx expand count", Grid_ParseLotSequence("0.01x5-0.02x3-0.05", seq), 9);
   CheckEq("seqx step1", seq[0], 0.01);
   CheckEq("seqx step5", seq[4], 0.01);
   CheckEq("seqx step6", seq[5], 0.02);
   CheckEq("seqx step8", seq[7], 0.02);
   CheckEq("seqx step9", seq[8], 0.05);
   CheckEq("seqx uppercase X",  Grid_ParseLotSequence("0.01X2-0.03", seq), 3);
   CheckEq("seqx inner spaces", Grid_ParseLotSequence("0.01 x2 - 0.03", seq), 3);
   CheckEq("seqx x0 invalid", Grid_ParseLotSequence("0.01x0-0.02", seq), 0);
   CheckEq("seqx trailing x invalid", Grid_ParseLotSequence("0.01x", seq), 0);
   CheckEq("seqx bare xN invalid", Grid_ParseLotSequence("x5", seq), 0);
   CheckEq("seqx fractional count invalid", Grid_ParseLotSequence("0.01x2.5", seq), 0);
   CheckEq("seqx garbage lot invalid", Grid_ParseLotSequence("0.01a-0.02", seq), 0);
   CheckEq("seqx over cap 200 invalid", Grid_ParseLotSequence("0.01x201", seq), 0);
   CheckEq("seqx at cap 200 ok", Grid_ParseLotSequence("0.01x200", seq), 200);

   //--- v14.2 FE-301: overlap-trim indexing — BOTH modes count OPEN orders
   //    (Chu nha 2026-07-26: mo 9 tia 2 con 7 -> lenh ke tiep la lenh so 8)
   CSequenceSizer sx;
   Check("seqx sizer init", sx.Init("0.01x5-0.02x3-0.05"));
   BasketSide bx;
   bx.count = 0;  CheckEq("seqx order #1 -> 0.01", sx.NextLot(bx), 0.01);
   bx.count = 5;  CheckEq("seqx order #6 -> 0.02", sx.NextLot(bx), 0.02);
   bx.count = 7;  CheckEq("seqx after trim 9->7: order #8 -> 0.02", sx.NextLot(bx), 0.02);
   bx.count = 8;  CheckEq("seqx order #9 -> 0.05", sx.NextLot(bx), 0.05);
   bx.count = 12; CheckEq("seqx beyond -> last 0.05 repeats", sx.NextLot(bx), 0.05);
   CheckEq("mart after trim 9->7: 0.01*1.5^7", Grid_MartingaleLot(0.01, 7, 1.5, 5),
           NormalizeDouble(0.01*MathPow(1.5,7), 2));   // v13 rule unchanged

   //--- v14.2.1 FIX-5: volume-constraint validation for lot chains
   double vl[];
   string why = "";
   Grid_ParseLotSequence("0.01x2-0.05", vl);
   CheckEq("FIX-5 chain tradable -> -1",   Grid_ValidateVolumes(vl, 0.01, 100, 0.01, why), -1);
   Grid_ParseLotSequence("0.01-0.005", vl);
   CheckEq("FIX-5 below min -> step 2",    Grid_ValidateVolumes(vl, 0.01, 100, 0.01, why), 2);
   Grid_ParseLotSequence("0.01-0.015", vl);
   CheckEq("FIX-5 off-step -> step 2",     Grid_ValidateVolumes(vl, 0.01, 100, 0.01, why), 2);
   Grid_ParseLotSequence("0.01-200", vl);
   CheckEq("FIX-5 above max -> step 2",    Grid_ValidateVolumes(vl, 0.01, 100, 0.01, why), 2);
   Grid_ParseLotSequence("0.1x3", vl);
   CheckEq("FIX-5 step 0.1 grid ok",       Grid_ValidateVolumes(vl, 0.01, 100, 0.01, why), -1);

   //--- v14.1 FE-203: DCA comment format "commentinput|n"
   Check("comment order1", Exec_BuildComment("EaBd", 1) == "EaBd|1");
   Check("comment order2", Exec_BuildComment("EaBd", 2) == "EaBd|2");
   Check("comment plain when idx=0", Exec_BuildComment("EaBd", 0) == "EaBd");

   //--- BD-002: async lifecycle — REQUEST accepted is not completion
   Check("BD-002 no evidence stays pending",
         !Exec_PendingReady(PENDING_EVIDENCE_NONE));
   Check("BD-002 REQUEST accepted alone stays pending",
         !Exec_PendingReady(PENDING_EVIDENCE_REQUEST));
   Check("BD-002 DEAL alone stays pending",
         !Exec_PendingReady(PENDING_EVIDENCE_DEAL));
   Check("BD-002 ORDER_DELETE alone stays pending",
         !Exec_PendingReady(PENDING_EVIDENCE_ORDER_DELETE));
   Check("BD-002 resulting position state may complete before REQUEST",
         Exec_PendingReady(PENDING_EVIDENCE_RESULT_STATE));
   Check("BD-002 close-volume full result observed",
         Exec_CloseVolumeResolved(0.10, 0.00, 0.10, 0.01));
   Check("BD-002 close-volume partial target observed",
         Exec_CloseVolumeResolved(0.10, 0.06, 0.04, 0.01));
   Check("BD-002 close-volume insufficient change stays pending",
         !Exec_CloseVolumeResolved(0.10, 0.08, 0.04, 0.01));
   Check("BD-002 close-volume zero target is not completion",
         !Exec_CloseVolumeResolved(0.10, 0.10, 0, 0.01));

   //--- v14.3 FE-401: money thresholds (TP positive, SL negative, 0 = off)
   Check("MG tp hit",      MG_MoneyTpHit(500, 500));
   Check("MG tp not",      !MG_MoneyTpHit(499.99, 500));
   Check("MG tp off",      !MG_MoneyTpHit(1000, 0));
   Check("MG sl hit",      MG_MoneySlHit(-500, -500));
   Check("MG sl not",      !MG_MoneySlHit(-499, -500));
   Check("MG sl off",      !MG_MoneySlHit(-1000, 0));

   //--- v14.3 FE-401: %-diff close-all — doc example: Buy +10, Sell -8, 2%
   Check("MG pct doc example (1.84>=0)", MG_PctDiffHit(10, -8, 2));
   Check("MG pct not enough (30%)",      !MG_PctDiffHit(10, -8, 30));
   Check("MG pct just over threshold",   MG_PctDiffHit(8.17, -8, 2));    // 8.17-8.16>0
   Check("MG pct just under threshold",  !MG_PctDiffHit(8.15, -8, 2));   // 8.15-8.16<0
   Check("MG pct sides swapped",         MG_PctDiffHit(-8, 10, 2));
   Check("MG pct no losing side",        !MG_PctDiffHit(10, 5, 2));
   Check("MG pct off",                   !MG_PctDiffHit(10, -8, 0));

   //--- v14.3 FE-402: daily target/limit ($ and % of day-start balance)
   Check("MG daily tp $",     MG_DailyTpHit(100, 100, 0, 0));
   Check("MG daily tp %",     MG_DailyTpHit(50, 0, 1000, 5));      // 5% of 1000
   Check("MG daily tp % not", !MG_DailyTpHit(49.9, 0, 1000, 5));
   Check("MG daily tp % no base", !MG_DailyTpHit(50, 0, 0, 5));    // no valid balance -> off
   Check("MG daily sl $",     MG_DailySlHit(-100, -100, 0, 0));
   Check("MG daily sl %",     MG_DailySlHit(-50, 0, 1000, -5));
   Check("MG daily all off",  !MG_DailyTpHit(1e9, 0, 0, 0) && !MG_DailySlHit(-1e9, 0, 0, 0));

   //--- v14.4 FE-403: HH:MM parse (PC/local time schedule)
   int mm = 0;
   Check("TL parse 07:00",      TL_ParseHHMM("07:00", mm) && mm == 420);
   Check("TL parse 7:05",       TL_ParseHHMM("7:05", mm) && mm == 425);
   Check("TL parse 23:59",      TL_ParseHHMM("23:59", mm) && mm == 1439);
   Check("TL parse 00:00",      TL_ParseHHMM("00:00", mm) && mm == 0);
   Check("TL parse spaces",     TL_ParseHHMM(" 07:30 ", mm) && mm == 450);
   Check("TL reject 24:00",     !TL_ParseHHMM("24:00", mm));
   Check("TL reject 12:60",     !TL_ParseHHMM("12:60", mm));
   Check("TL reject no colon",  !TL_ParseHHMM("1200", mm));
   Check("TL reject 1-digit minute", !TL_ParseHHMM("07:0", mm));
   Check("TL reject letters",   !TL_ParseHHMM("ab:cd", mm));
   Check("TL reject 1a hour",   !TL_ParseHHMM("1a:00", mm));
   Check("TL reject empty",     !TL_ParseHHMM("", mm));

   //--- v14.4 FE-403: window membership ([start, end), overnight support)
   Check("TL in normal window",        TL_InWindow(8*60, 7*60, 11*60));
   Check("TL start inclusive",         TL_InWindow(7*60, 7*60, 11*60));
   Check("TL end exclusive",           !TL_InWindow(11*60, 7*60, 11*60));
   Check("TL outside normal",          !TL_InWindow(12*60, 7*60, 11*60));
   Check("TL overnight late side",     TL_InWindow(23*60, 22*60, 2*60));
   Check("TL overnight early side",    TL_InWindow(1*60, 22*60, 2*60));
   Check("TL overnight midday out",    !TL_InWindow(12*60, 22*60, 2*60));
   Check("TL empty window never in",   !TL_InWindow(10*60, 10*60, 10*60));

   //--- v14.5 FE-404: mobile-control command mapping
   Check("MC stop all",   MC_Command(ORDER_TYPE_BUY_STOP,   999999) == MC_STOP_ALL);
   Check("MC resume",     MC_Command(ORDER_TYPE_BUY_STOP,   666666) == MC_RESUME);
   Check("MC cycle off",  MC_Command(ORDER_TYPE_BUY_STOP,   888888) == MC_CYCLE_OFF);
   Check("MC cycle on",   MC_Command(ORDER_TYPE_SELL_LIMIT, 888888) == MC_CYCLE_ON);
   Check("MC stop buy",   MC_Command(ORDER_TYPE_BUY_STOP,   555555) == MC_STOP_BUY);
   Check("MC stop sell",  MC_Command(ORDER_TYPE_SELL_LIMIT, 555555) == MC_STOP_SELL);
   Check("MC wrong type 999999",  MC_Command(ORDER_TYPE_SELL_LIMIT, 999999) == MC_NONE);
   Check("MC wrong type 666666",  MC_Command(ORDER_TYPE_SELL_LIMIT, 666666) == MC_NONE);
   Check("MC other order type",   MC_Command(ORDER_TYPE_SELL_STOP,  888888) == MC_NONE);
   Check("MC normal price",       MC_Command(ORDER_TYPE_BUY_STOP,   3350.5) == MC_NONE);
   Check("MC tolerance in",       MC_Command(ORDER_TYPE_BUY_STOP, 999999.0001) == MC_STOP_ALL);
   Check("MC tolerance out",      MC_Command(ORDER_TYPE_BUY_STOP, 999000) == MC_NONE);

   //--- v14.5 FE-404: apply semantics (resume clears pauses; idempotent)
   bool rs = false, pb = false, ps = false, nc = true;
   Check("MC apply stop-all",     MC_Apply(MC_STOP_ALL, rs, pb, ps, nc) && rs);
   Check("MC apply idempotent",   !MC_Apply(MC_STOP_ALL, rs, pb, ps, nc));   // no change 2nd time
   Check("MC apply stop buy",     MC_Apply(MC_STOP_BUY, rs, pb, ps, nc) && pb);
   Check("MC apply cycle off",    MC_Apply(MC_CYCLE_OFF, rs, pb, ps, nc) && !nc);
   Check("MC apply resume clears all", MC_Apply(MC_RESUME, rs, pb, ps, nc) && !rs && !pb && !ps);
   Check("MC apply cycle unaffected by resume", !nc);   // resume does NOT touch NewCycle
   Check("MC apply none",         !MC_Apply(MC_NONE, rs, pb, ps, nc));

   //--- v14.6 FE-405: WMF applied price (Pine src)
   CheckEq("WMF price close",    WMF_Price(PRICE_CLOSE,    1, 4, 0, 2), 2);
   CheckEq("WMF price open",     WMF_Price(PRICE_OPEN,     1, 4, 0, 2), 1);
   CheckEq("WMF price median",   WMF_Price(PRICE_MEDIAN,   1, 4, 0, 2), 2);
   CheckEq("WMF price typical",  WMF_Price(PRICE_TYPICAL,  1, 4, 2, 3), 3);
   CheckEq("WMF price weighted", WMF_Price(PRICE_WEIGHTED, 1, 4, 0, 2), 2);

   //--- v14.6 FE-405: WMF recursion vs HAND-COMPUTED reference
   //    (atrM = 2 co dinh, EMA len 2 -> alpha 2/3; chuoi lat trend 2 lan)
   SWmfState ws;
   WMF_Reset(ws);
   double al = 2.0 / 3.0;
   WMF_Step(ws, 100, 2, al);
   Check("WMF b1 seed: stop 98 UP ema 100", ws.uptrend && MathAbs(ws.stop - 98) < 1e-9 && MathAbs(ws.ema - 100) < 1e-9);
   WMF_Step(ws, 101, 2, al);
   Check("WMF b2 ratchet: stop 99", ws.uptrend && MathAbs(ws.stop - 99) < 1e-9 && MathAbs(ws.ema - 100.6666667) < 1e-6);
   WMF_Step(ws, 99, 2, al);
   Check("WMF b3 cham stop van UP (>=0)", ws.uptrend && MathAbs(ws.stop - 99) < 1e-9);
   double pe = ws.ema, ps2 = ws.stop;
   WMF_Step(ws, 96, 2, al);
   Check("WMF b4 flip DOWN, reset stop 98", !ws.uptrend && MathAbs(ws.stop - 98) < 1e-9);
   Check("WMF b4 SELL cross (crossunder)", ws.ema < ws.stop && pe >= ps2);
   WMF_Step(ws, 95, 2, al);
   Check("WMF b5 stop ratchet xuong 97", !ws.uptrend && MathAbs(ws.stop - 97) < 1e-9);
   pe = ws.ema; ps2 = ws.stop;
   WMF_Step(ws, 99, 2, al);
   Check("WMF b6 flip UP, stop 97", ws.uptrend && MathAbs(ws.stop - 97) < 1e-9);
   Check("WMF b6 BUY cross (crossover)", ws.ema > ws.stop && pe <= ps2);
   Check("WMF b6 ema ref 97.90946", MathAbs(ws.ema - 97.9094650) < 1e-6);

   //--- v14.7 FE-407: distance chain (vi du cua Chu nha: 10x3-15x2-20)
   double gaps[];
   Grid_ParseLotSequence("10x3-15x2-20", gaps);
   CheckEq("D-chain expand 6 gaps", ArraySize(gaps), 6);
   CheckEq("D-chain order#2 (count1) -> 10 pip = 100pt", Grid_ChainDistancePoints(1, gaps), 100);
   CheckEq("D-chain order#4 (count3) -> 10 pip",         Grid_ChainDistancePoints(3, gaps), 100);
   CheckEq("D-chain order#5 (count4) -> 15 pip = 150pt", Grid_ChainDistancePoints(4, gaps), 150);
   CheckEq("D-chain order#7 (count6) -> 20 pip = 200pt", Grid_ChainDistancePoints(6, gaps), 200);
   CheckEq("D-chain beyond -> 20 pip repeats",           Grid_ChainDistancePoints(12, gaps), 200);
   CheckEq("D-chain after trim 9->7: order#8 dung gap[6] -> 20 pip", Grid_ChainDistancePoints(7, gaps), 200);
   double emptyGaps[];
   CheckEq("D-chain empty -> 0", Grid_ChainDistancePoints(1, emptyGaps), 0);

   //--- v14.7 FE-408: multiplier chain — THEORETICAL closed-form lot
   double mult[];
   Grid_ParseLotSequence("1.03x3-1.3x4-1.25-1.5", mult);
   CheckEq("M-chain expand 9 factors", ArraySize(mult), 9);
   CheckEq("M-chain order#2: 0.01*1.03",  Grid_ChainLot(0.01, 1, mult, 100), 0.0103, 1e-12);
   CheckEq("M-chain order#5: *1.03^3*1.3", Grid_ChainLot(0.01, 4, mult, 100), 0.01 * MathPow(1.03, 3) * 1.3, 1e-12);
   CheckEq("M-chain order#10: du 9 he so",  Grid_ChainLot(0.01, 9, mult, 100),
           0.01 * MathPow(1.03, 3) * MathPow(1.3, 4) * 1.25 * 1.5, 1e-12);
   CheckEq("M-chain order#12: lap 1.5",     Grid_ChainLot(0.01, 11, mult, 100),
           0.01 * MathPow(1.03, 3) * MathPow(1.3, 4) * 1.25 * MathPow(1.5, 3), 1e-12);
   // anti-stuck: he so nho khong bi ket boi lam tron trung gian
   double small[];
   Grid_ParseLotSequence("1.03", small);
   Check("M-chain anti-stuck: 1.03^10 > 1.03 don le", Grid_ChainLot(0.01, 10, small, 100) > 0.0134);
   CheckEq("M-chain no-cap 1.03^200 duoi MaxLot", Grid_ChainLot(0.01, 200, small, 5), 0.01 * MathPow(1.03, 200), 1e-9);
   CheckEq("M-chain MaxLot cap (1.03^300)", Grid_ChainLot(0.01, 300, small, 5), 5.0);

   //====================================================================
   //  v14.7.2 deep review — BD-R1..R9 (37 asserts)
   //  Only the PURE parts are asserted here. BD-R3 (SeedExtreme anchor
   //  rule), BD-R7 (RefreshFloating compaction) and BD-R8 (DrawLevels
   //  cadence) need live positions / a chart: see the terminal checklist
   //  in docs/vibecode/VERIFY_REPORT-v14.7.2.md.
   //====================================================================

   //--- TIP-501 / BD-R2: Slippage_ is a point input -> obeys rule 8 -----
   //    Reference (2-digit gold, FX): scale 1 -> byte-identical to v13.
   CheckEq("BD-R2 non-gold scale 1 keeps v13 value", (double)Exec_Deviation(3, 1), 3);
   CheckEq("BD-R2 3-digit gold: 3 ref points = 30 broker points", (double)Exec_Deviation(3, 10), 30);
   CheckEq("BD-R2 zero slippage stays zero",     (double)Exec_Deviation(0, 10), 0);
   CheckEq("BD-R2 negative slippage clamped",    (double)Exec_Deviation(-5, 10), 0);
   CheckEq("BD-R2 scale 0 clamped to 1",         (double)Exec_Deviation(3, 0), 3);
   CheckEq("BD-R2 negative scale clamped to 1",  (double)Exec_Deviation(3, -2), 3);
   //    The cross-symbol variant must agree with the chart wrapper on _Symbol.
   CheckEq("BD-R2 Sym_PointScaleFor(_Symbol) == Sym_PointScale()",
           Sym_PointScaleFor(_Symbol), Sym_PointScale());

   //--- TIP-502 / BD-R4: daily halt deadline = next midnight + delay ----
   datetime day0 = D'2026.08.11 00:00:00';
   Check("BD-R4 no delay -> next midnight",   MG_HaltDeadline(day0, 0) == day0 + 86400);
   Check("BD-R4 30 min delay",                MG_HaltDeadline(day0, 30) == day0 + 86400 + 1800);
   Check("BD-R4 full day delay",              MG_HaltDeadline(day0, 1440) == day0 + 172800);
   //    A negative delay must never pull the deadline back into today, which
   //    would cancel the halt on the very next tick.
   Check("BD-R4 negative delay clamped to 0", MG_HaltDeadline(day0, -15) == day0 + 86400);
   Check("BD-R4 deadline always in the future", MG_HaltDeadline(day0, -600) > day0);

   //--- TIP-503 / BD-R5: failed pending delete backs off, never storms --
   Check("BD-R5 delete retry backoff is positive", BD_MC_DELETE_RETRY_SEC > 0);

   //--- TIP-506 / BD-R1: per-intent hard timeout (Chu nha 11/08/2026) ---
   //    CLOSE/MODIFY are idempotent -> release early (10s). OPEN is not ->
   //    keep the conservative 30s or a real order could be duplicated.
   CheckEq("BD-R1 OPEN_BUY keeps 30s",   Exec_HardTimeoutSec(INTENT_OPEN_BUY),  BD_ASYNC_HARD_TIMEOUT_SEC);
   CheckEq("BD-R1 OPEN_SELL keeps 30s",  Exec_HardTimeoutSec(INTENT_OPEN_SELL), BD_ASYNC_HARD_TIMEOUT_SEC);
   CheckEq("BD-R1 CLOSE_TICKET -> 10s",  Exec_HardTimeoutSec(INTENT_CLOSE_TICKET), BD_ASYNC_CLOSE_HARD_TIMEOUT_SEC);
   CheckEq("BD-R1 MODIFY_SLTP -> 10s",   Exec_HardTimeoutSec(INTENT_MODIFY_SLTP),  BD_ASYNC_CLOSE_HARD_TIMEOUT_SEC);
   CheckEq("BD-R1 NONE falls back to the short timeout",
           Exec_HardTimeoutSec(INTENT_NONE), BD_ASYNC_CLOSE_HARD_TIMEOUT_SEC);
   Check("BD-R1 soft timeout fires before the close hard timeout",
         BD_ASYNC_TIMEOUT_SEC < BD_ASYNC_CLOSE_HARD_TIMEOUT_SEC);
   Check("BD-R1 close unlocks before open",
         BD_ASYNC_CLOSE_HARD_TIMEOUT_SEC < BD_ASYNC_HARD_TIMEOUT_SEC);
   Check("BD-R1 asymmetry holds through the function",
         Exec_HardTimeoutSec(INTENT_CLOSE_TICKET) < Exec_HardTimeoutSec(INTENT_OPEN_BUY));

   //--- TIP-508 / BD-R6: ONE ownership rule for positions AND deals -----
   //    Same predicate now feeds Rebuild(), SeedDayProfit() and the
   //    OnTradeTransaction booking, so floating and realized P/L can never
   //    disagree about which orders belong to the daily net.
   Check("BD-R6 own magic owned (hand off)",   Basket_OwnsMagic(1111, 1111, false));
   Check("BD-R6 own magic owned (hand on)",    Basket_OwnsMagic(1111, 1111, true));
   Check("BD-R6 default: manual magic-0 ignored", !Basket_OwnsMagic(0, 1111, false));
   Check("BD-R6 flag_Hand_Ord: manual magic-0 counted", Basket_OwnsMagic(0, 1111, true));
   Check("BD-R6 foreign magic never owned (hand off)", !Basket_OwnsMagic(2222, 1111, false));
   Check("BD-R6 foreign magic never owned (hand on)",  !Basket_OwnsMagic(2222, 1111, true));
   Check("BD-R6 bot configured with Magic=0 owns its own deals", Basket_OwnsMagic(0, 0, false));

   //--- TIP-509 / BD-R9: hedge gates a NEW series, never a DCA add ------
   //    v13 rule preserved for new series...
   Check("BD-R9 hedge ON: opposite side never blocks a new series",
         Hedge_AllowsNewSeries(true, 5));
   Check("BD-R9 hedge OFF + opposite flat: new series allowed",
         Hedge_AllowsNewSeries(false, 0));
   Check("BD-R9 hedge OFF + opposite open: new series BLOCKED (v13)",
         !Hedge_AllowsNewSeries(false, 3));
   Check("BD-R9 impossible negative count treated as flat",
         Hedge_AllowsNewSeries(false, -1));
   //    ...while a DCA add depends ONLY on its own side being open.
   Check("BD-R9 open side may add a grid leg",   Hedge_AllowsGridAdd(2));
   Check("BD-R9 flat side has nothing to add to", !Hedge_AllowsGridAdd(0));

   //    Regression: reconstruct the OLD gate and show it deadlocked BOTH
   //    sides at once. Held as live code, not prose, so nobody re-adds it.
   bool useHedge  = false;
   int  buyCount  = 3;
   int  sellCount = 2;
   bool oldBuyGate  = (useHedge || sellCount == 0);   // gated buy DCA on SELL
   bool oldSellGate = (useHedge || buyCount  == 0);   // gated sell DCA on BUY
   Check("BD-R9 the old gate froze BOTH sides simultaneously",
         !oldBuyGate && !oldSellGate);
   Check("BD-R9 the new gate frees BOTH sides",
         Hedge_AllowsGridAdd(buyCount) && Hedge_AllowsGridAdd(sellCount));
   //    ...and the no-hedge protection is NOT weakened: in that very same
   //    state a NEW series is still refused.
   Check("BD-R9 DCA freed but a new opposite series still refused",
         Hedge_AllowsGridAdd(buyCount) && !Hedge_AllowsNewSeries(useHedge, sellCount));


   //--- BD-R10: account-wide closes preserve position ownership ----------
   CheckEq("BD-R10 own position keeps bot magic",    (double)Exec_CloseRequestMagic(1111), 1111);
   CheckEq("BD-R10 foreign position stays foreign",  (double)Exec_CloseRequestMagic(2222), 2222);
   CheckEq("BD-R10 manual position stays magic-0",   (double)Exec_CloseRequestMagic(0), 0);
   CheckEq("BD-R10 invalid negative magic clamps 0", (double)Exec_CloseRequestMagic(-1), 0);

   PrintFormat("BlackDragon v14 unit tests: %d passed, %d failed", g_pass, g_fail);
   if(g_fail == 0) Print("ALL GREEN — safe to proceed to backtest comparison (golden baseline).");
}
