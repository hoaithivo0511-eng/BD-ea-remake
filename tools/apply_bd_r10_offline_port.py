from pathlib import Path
import re

ROOT = Path.cwd()
EXEC = ROOT / "BlackDragon_v14/Include/BlackDragon/ExecutionLayer.mqh"
MQL_TEST = ROOT / "BlackDragon_v14/Scripts/BlackDragon/Tests/RunTests.mq5"
OFFLINE = ROOT / "BlackDragon_v14/Scripts/BlackDragon/Tests/offline_suite.cpp"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, got {count}")
    return text.replace(old, new, 1)


# BD-R10: preserve the selected position's ownership on account-wide closes.
ex = EXEC.read_text(encoding="utf-8")
helper = """//--- BD-R10 (deep review 14/08/2026): preserve close ownership ------
//    A zero-initialized MqlTradeRequest makes the closing DEAL magic 0.
//    CloseAllAccount() can close this EA, manual, and foreign-EA positions,
//    so assigning the chart Magic to every request would corrupt ownership
//    in the opposite direction. Preserve the selected position's magic:
//    own positions stay owned, manual stays 0, foreign stays foreign.
ulong Exec_CloseRequestMagic(const long positionMagic)
{
   return positionMagic > 0 ? (ulong)positionMagic : 0;
}

"""
ex = replace_once(
    ex,
    "class CExecutionLayer\n{",
    helper + "class CExecutionLayer\n{",
    "insert Exec_CloseRequestMagic helper",
)
ex = replace_once(
    ex,
    """      long type = PositionGetInteger(POSITION_TYPE);
      MqlTradeRequest req; MqlTradeResult res;
      ZeroMemory(req); ZeroMemory(res);
      req.action       = TRADE_ACTION_DEAL;
      req.symbol       = sym;
""",
    """      long type = PositionGetInteger(POSITION_TYPE);
      long positionMagic = PositionGetInteger(POSITION_MAGIC);
      MqlTradeRequest req; MqlTradeResult res;
      ZeroMemory(req); ZeroMemory(res);
      req.action       = TRADE_ACTION_DEAL;
      req.symbol       = sym;
""",
    "capture position magic in ClosePositionEx",
)
ex = replace_once(
    ex,
    """      req.deviation    = Exec_Deviation(Slippage_, Sym_PointScaleFor(sym));
      req.type_filling = FillingFor(sym);
""",
    """      req.deviation    = Exec_Deviation(Slippage_, Sym_PointScaleFor(sym));
      req.magic        = Exec_CloseRequestMagic(positionMagic);  // BD-R10: preserve owner
      req.type_filling = FillingFor(sym);
""",
    "wire preserved magic into ClosePositionEx",
)
EXEC.write_text(ex, encoding="utf-8", newline="\n")

# Native MQL locking tests for BD-R10.
rt = MQL_TEST.read_text(encoding="utf-8")
bdr10_mql = """
   //--- BD-R10: account-wide closes preserve position ownership ----------
   CheckEq("BD-R10 own position keeps bot magic",    (double)Exec_CloseRequestMagic(1111), 1111);
   CheckEq("BD-R10 foreign position stays foreign",  (double)Exec_CloseRequestMagic(2222), 2222);
   CheckEq("BD-R10 manual position stays magic-0",   (double)Exec_CloseRequestMagic(0), 0);
   CheckEq("BD-R10 invalid negative magic clamps 0", (double)Exec_CloseRequestMagic(-1), 0);

"""
rt = replace_once(
    rt,
    '   PrintFormat("BlackDragon v14 unit tests: %d passed, %d failed", g_pass, g_fail);',
    bdr10_mql
    + '   PrintFormat("BlackDragon v14 unit tests: %d passed, %d failed", g_pass, g_fail);',
    "append BD-R10 MQL locking tests",
)
MQL_TEST.write_text(rt, encoding="utf-8", newline="\n")

# Offline pure surfaces needed by the exact 37-assert BD-R1..R9 port.
off = OFFLINE.read_text(encoding="utf-8")
off = replace_once(
    off,
    "// BlackDragon v14.0.2 — offline test harness (Vibecode RRI-T, sandbox e2e)",
    "// BlackDragon v14.7.2 — offline test harness (Vibecode RRI-T, sandbox e2e)",
    "update offline suite header",
)
pure = r"""
// ---- v14.7.2 BD-R1..R10 deep-review pure surfaces -------------------------
#define BD_ASYNC_TIMEOUT_SEC 5
#define BD_ASYNC_HARD_TIMEOUT_SEC 30
#define BD_ASYNC_CLOSE_HARD_TIMEOUT_SEC 10
#define BD_MC_DELETE_RETRY_SEC 5

unsigned long Exec_Deviation(const int slippagePoints, const int pointScale)
{
   int s = slippagePoints < 0 ? 0 : slippagePoints;
   int k = pointScale < 1 ? 1 : pointScale;
   return (unsigned long)(s * k);
}
int Exec_HardTimeoutSec(const eIntent action)
{
   if(action == INTENT_OPEN_BUY || action == INTENT_OPEN_SELL)
      return BD_ASYNC_HARD_TIMEOUT_SEC;
   return BD_ASYNC_CLOSE_HARD_TIMEOUT_SEC;
}
long MG_HaltDeadline(const long dayStart, const int delayMin)
{
   int d = delayMin < 0 ? 0 : delayMin;
   return dayStart + 86400L + (long)d * 60L;
}
bool Basket_OwnsMagic(const long dealMagic, const long botMagic, const bool handOrders)
{
   return dealMagic == botMagic || (dealMagic == 0 && handOrders);
}
bool Hedge_AllowsNewSeries(const bool useHedge, const int oppositeCount)
{
   return useHedge || oppositeCount <= 0;
}
bool Hedge_AllowsGridAdd(const int ownCount)
{
   return ownCount > 0;
}
int Sym_PointScaleForModel(const bool autoGoldPip, const bool isGold, const double point)
{
   if(!autoGoldPip) return 1;
   return Sym_PointScalePure(isGold, point);
}
unsigned long Exec_CloseRequestMagic(const long positionMagic)
{
   return positionMagic > 0 ? (unsigned long)positionMagic : 0;
}

"""
off = replace_once(
    off,
    "\nint main()\n",
    "\n" + pure + "int main()\n",
    "insert deep-review pure surfaces",
)

tests = r"""
   // ========== PART 16: v14.7.2 BD-R1..R9 — exact 37-assert port ===========
   // BD-R2: Slippage_ is a point input and obeys PointScale.
   CheckEq("BD-R2 non-gold scale 1 keeps v13 value", (double)Exec_Deviation(3, 1), 3);
   CheckEq("BD-R2 3-digit gold: 3 ref points = 30 broker points", (double)Exec_Deviation(3, 10), 30);
   CheckEq("BD-R2 zero slippage stays zero",     (double)Exec_Deviation(0, 10), 0);
   CheckEq("BD-R2 negative slippage clamped",    (double)Exec_Deviation(-5, 10), 0);
   CheckEq("BD-R2 scale 0 clamped to 1",         (double)Exec_Deviation(3, 0), 3);
   CheckEq("BD-R2 negative scale clamped to 1",  (double)Exec_Deviation(3, -2), 3);
   CheckEq("BD-R2 Sym_PointScaleFor(_Symbol) == Sym_PointScale()",
           Sym_PointScaleForModel(true, true, 0.001), Sym_PointScalePure(true, 0.001));

   // BD-R4: daily halt deadline = next midnight + delay.
   long day0 = 1770768000L;
   Check("BD-R4 no delay -> next midnight",   MG_HaltDeadline(day0, 0) == day0 + 86400);
   Check("BD-R4 30 min delay",                MG_HaltDeadline(day0, 30) == day0 + 86400 + 1800);
   Check("BD-R4 full day delay",              MG_HaltDeadline(day0, 1440) == day0 + 172800);
   Check("BD-R4 negative delay clamped to 0", MG_HaltDeadline(day0, -15) == day0 + 86400);
   Check("BD-R4 deadline always in the future", MG_HaltDeadline(day0, -600) > day0);

   // BD-R5: failed pending delete backs off instead of storming.
   Check("BD-R5 delete retry backoff is positive", BD_MC_DELETE_RETRY_SEC > 0);

   // BD-R1: per-intent hard timeout.
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

   // BD-R6: one ownership predicate for floating and realized P/L.
   Check("BD-R6 own magic owned (hand off)",   Basket_OwnsMagic(1111, 1111, false));
   Check("BD-R6 own magic owned (hand on)",    Basket_OwnsMagic(1111, 1111, true));
   Check("BD-R6 default: manual magic-0 ignored", !Basket_OwnsMagic(0, 1111, false));
   Check("BD-R6 flag_Hand_Ord: manual magic-0 counted", Basket_OwnsMagic(0, 1111, true));
   Check("BD-R6 foreign magic never owned (hand off)", !Basket_OwnsMagic(2222, 1111, false));
   Check("BD-R6 foreign magic never owned (hand on)",  !Basket_OwnsMagic(2222, 1111, true));
   Check("BD-R6 bot configured with Magic=0 owns its own deals", Basket_OwnsMagic(0, 0, false));

   // BD-R9: hedge gates new series, never an existing-side DCA add.
   Check("BD-R9 hedge ON: opposite side never blocks a new series",
         Hedge_AllowsNewSeries(true, 5));
   Check("BD-R9 hedge OFF + opposite flat: new series allowed",
         Hedge_AllowsNewSeries(false, 0));
   Check("BD-R9 hedge OFF + opposite open: new series BLOCKED (v13)",
         !Hedge_AllowsNewSeries(false, 3));
   Check("BD-R9 impossible negative count treated as flat",
         Hedge_AllowsNewSeries(false, -1));
   Check("BD-R9 open side may add a grid leg",   Hedge_AllowsGridAdd(2));
   Check("BD-R9 flat side has nothing to add to", !Hedge_AllowsGridAdd(0));
   bool useHedge  = false;
   int  buyCount  = 3;
   int  sellCount = 2;
   bool oldBuyGate  = (useHedge || sellCount == 0);
   bool oldSellGate = (useHedge || buyCount  == 0);
   Check("BD-R9 the old gate froze BOTH sides simultaneously",
         !oldBuyGate && !oldSellGate);
   Check("BD-R9 the new gate frees BOTH sides",
         Hedge_AllowsGridAdd(buyCount) && Hedge_AllowsGridAdd(sellCount));
   Check("BD-R9 DCA freed but a new opposite series still refused",
         Hedge_AllowsGridAdd(buyCount) && !Hedge_AllowsNewSeries(useHedge, sellCount));

   // ========== PART 17: BD-R10 ownership-preserving account close ===========
   CheckEq("BD-R10 own position keeps bot magic",    (double)Exec_CloseRequestMagic(1111), 1111);
   CheckEq("BD-R10 foreign position stays foreign",  (double)Exec_CloseRequestMagic(2222), 2222);
   CheckEq("BD-R10 manual position stays magic-0",   (double)Exec_CloseRequestMagic(0), 0);
   CheckEq("BD-R10 invalid negative magic clamps 0", (double)Exec_CloseRequestMagic(-1), 0);

"""
off = replace_once(
    off,
    '   printf("BlackDragon v14.7.1 offline suite: %d passed, %d failed\\n", g_pass, g_fail);',
    tests
    + '   printf("BlackDragon v14.7.2 offline suite: %d passed, %d failed\\n", g_pass, g_fail);',
    "append 37 ported assertions and four BD-R10 tests",
)
OFFLINE.write_text(off, encoding="utf-8", newline="\n")

# Mechanical parity: same 37 labels in the same order.
rt_now = MQL_TEST.read_text(encoding="utf-8")
off_now = OFFLINE.read_text(encoding="utf-8")
mql37 = rt_now.split("v14.7.2 deep review — BD-R1..R9 (37 asserts)", 1)[1]
mql37 = mql37.split("//--- BD-R10:", 1)[0]
cpp37 = off_now.split("PART 16: v14.7.2 BD-R1..R9 — exact 37-assert port", 1)[1]
cpp37 = cpp37.split("PART 17: BD-R10", 1)[0]
rx = re.compile(r'\bCheck(?:Eq)?\("([^"]+)"')
mql_names = rx.findall(mql37)
cpp_names = rx.findall(cpp37)
if len(mql_names) != 37:
    raise SystemExit(f"MQL source block is not 37 asserts: {len(mql_names)}")
if len(cpp_names) != 37:
    raise SystemExit(f"C++ port block is not 37 asserts: {len(cpp_names)}")
if mql_names != cpp_names:
    raise SystemExit(f"assert parity failed; MQL={mql_names}; C++={cpp_names}")

cpp10 = off_now.split("PART 17: BD-R10", 1)[1]
cpp10 = cpp10.split('printf("BlackDragon', 1)[0]
if len(rx.findall(cpp10)) != 4:
    raise SystemExit("BD-R10 offline block must contain exactly four asserts")

print("PATCH_PARITY_OK: 37/37 BD-R1..R9 names match in exact order; BD-R10=4")
