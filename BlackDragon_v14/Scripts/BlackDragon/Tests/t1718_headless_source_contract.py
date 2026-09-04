#!/usr/bin/env python3
"""T17.18 source contract: the canonical EA is intentionally headless."""

from pathlib import Path
import re
import sys


REPO = Path(__file__).resolve().parents[4]
PRODUCT = REPO / "BlackDragon_v14"
ENTRY = PRODUCT / "Experts" / "BlackDragon" / "BlackDragon.mq5"
INCLUDE = PRODUCT / "Include" / "BlackDragon"

checks = 0
failures: list[str] = []


def check(name: str, condition: bool, detail: str = "") -> None:
    global checks
    checks += 1
    if not condition:
        failures.append(f"{name}: {detail}".rstrip(": "))


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


entry = read(ENTRY)
config = read(INCLUDE / "Config.mqh")
wmf = read(INCLUDE / "WmfSignal.mqh")
wmf_overlay_path = INCLUDE / "WmfSignalOverlay.mqh"
wmf_overlay = read(wmf_overlay_path)
strategy = read(INCLUDE / "Strategy.mqh")
strategy_base = read(INCLUDE / "StrategyT176Base.mqh")
persistence = read(INCLUDE / "Persistence.mqh")
recovery_exit = read(INCLUDE / "Recovery" / "RecoveryExitCoordinatorT13Base.mqh")

production_files = [ENTRY, *sorted(INCLUDE.rglob("*.mqh"))]
production_text = "\n".join(read(path) for path in production_files)

retired_inputs = {
    "X1_", "Y1_", "fDraw", "FontSizeMark",
    "FontNameMark", "ColorText", "ColorFonRec", "FontSizeButt",
    "FontNameButt", "ColorButt", "cCIP",
}
present_inputs = sorted(
    name for name in retired_inputs
    if re.search(rf"^\s*input\b[^;\n]*\b{re.escape(name)}\b", production_text, re.MULTILINE)
)
check("all 11 dashboard inputs are absent", not present_inputs,
      ", ".join(present_inputs))

input_rows = re.findall(r"^\s*input\s+([^\n]+)", production_text, re.MULTILINE)
parameter_rows = [row for row in input_rows if not row.lstrip().startswith("group")]
check("dashboard removal remains 143 parameters plus one T17.19 risk input",
      len(parameter_rows) == 144, f"found {len(parameter_rows)}")

check("ShowWmfSignals remains an owner-selectable signal overlay input",
      re.search(r"^\s*input\s+bool\s+ShowWmfSignals\s*=\s*true\s*;", config,
                re.MULTILINE) is not None)

check("Panel implementation is deleted", not (INCLUDE / "Panel.mqh").exists())
check("composition root has no panel or chart-event lifecycle",
      all(token not in entry for token in (
          "Panel.mqh", "CPanel", "g_panel", "OnChartEvent",
      )))
non_overlay_text = "\n".join(
    read(path) for path in production_files if path != wmf_overlay_path
)
check("chart-object APIs are isolated to the WMF signal overlay",
      not re.search(
          r"\b(?:ObjectCreate|ObjectDelete|ObjectsDeleteAll|ObjectFind|ObjectMove|"
          r"ObjectSetInteger|ObjectSetString|ObjectGetString|ChartRedraw)\s*\(",
          non_overlay_text,
      ))
check("WMF overlay renders arrows only",
      "OBJ_ARROW" in wmf_overlay
      and all(token not in wmf_overlay for token in (
          "OBJ_BUTTON", "OBJ_LABEL", "OBJ_RECTANGLE_LABEL", "OBJ_HLINE",
          "ChartRedraw", "OnChartEvent", "CHARTEVENT_",
      )))

required_timer_tokens = (
    "EventSetMillisecondTimer(BD_SERVICE_TIMER_MS)",
    "g_news.Refresh()", "g_exec.Watchdog()", "g_recovery.FlushPersistence()",
    "g_recoveryExit.Drive(", "g_mobile.Scan(&g_exec)",
    "g_basket.CheckDayRollover(", "Persist_Save()",
)
missing_timer = [token for token in required_timer_tokens if token not in entry]
check("non-visual service timer responsibilities are preserved",
      not missing_timer, ", ".join(missing_timer))

check("WMF crossover and optional signal-marker semantics are preserved",
      "m_pendingCross = buy ? 1 : (sell ? -1 : 0);" in wmf
      and "if(!ShowWmfSignals ||" in wmf
      and "TakePendingMarks" in wmf
      and "g_wmfOverlay.Mark" in entry)

check("non-visual tester performs no WMF allocation or chart-object work",
      "MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE)" in wmf
      and "MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE)" in wmf_overlay
      and "g_wmfOverlay.Enabled()" in entry)

for label, text in (("current", strategy), ("base", strategy_base)):
    check(f"{label} Strategy has a headless OnTick contract",
          "void OnTick(const EAContext &ctx)" in text
          and "CPanel" not in text and "panel" not in text.lower()
          and "Cfg.EditLot" not in text)

check("retired persistence slots keep the existing binary layout",
      all(token in persistence for token in (
          "reservedTradeBuy", "reservedTradeSell", "reservedEditLot",
      ))
      and all(token not in persistence for token in (
          "Cfg.TradeBuy  = st.", "Cfg.TradeSell = st.", "Cfg.EditLot",
      )))

expected_reason_values = {
    "NONE": 0, "RETIRED_CHART_CONTROL": 1, "LEGACY_TP": 2,
    "LEGACY_SL": 3, "LEGACY_TRAIL": 4, "LEGACY_OVERLAP": 5,
    "GUARD_SIDE": 6, "GUARD_MAGIC": 7, "GUARD_DAILY": 8,
    "EXTERNAL_CORE": 9, "EXTERNAL_RECOVERY": 10,
}
bad_reasons = []
for name, value in expected_reason_values.items():
    if not re.search(rf"recovery_EXIT_REASON_{name}\s*=\s*{value}\b", recovery_exit):
        bad_reasons.append(f"{name}!={value}")
check("persisted exit-reason numeric values do not shift", not bad_reasons,
      ", ".join(bad_reasons))

check("service timer cadence remains behavior-compatible",
      re.search(r"#define\s+BD_SERVICE_TIMER_MS\s+500\b", config) is not None
      and "BD_PANEL_TIMER_MS" not in production_text)

print(f"T17.18 headless source contract: {checks - len(failures)} passed, {len(failures)} failed")
for failure in failures:
    print(f"FAIL: {failure}")
if failures:
    sys.exit(1)
print("ALL GREEN — dashboard UI is absent, WMF arrows and trading services remain bound.")
