#!/usr/bin/env python3
"""T17.19 source composition and owner-amended admission contract."""

from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[3]


def read(rel: str) -> str:
    path = ROOT / rel
    return path.read_text(encoding="utf-8") if path.is_file() else ""


policy = read("Include/BlackDragon/Recovery/RecoveryT1719ReentryPolicy.mqh")
persist = read("Include/BlackDragon/Recovery/RecoveryT1719ReentryPersistence.mqh")
stack = read("Include/BlackDragon/Recovery/RecoveryArcsStackT1719Reentry.mqh")
engine = read("Include/BlackDragon/Recovery/RecoveryEngine.mqh")
dca = read("Include/BlackDragon/Recovery/RecoveryDcaT1713.mqh")
strategy = read("Include/BlackDragon/Strategy.mqh")
strategy_base = read("Include/BlackDragon/StrategyT176Base.mqh")
config = read("Include/BlackDragon/Recovery/RecoveryT16ConfigT177C5Impl.mqh")
arcs_persist = read("Include/BlackDragon/Recovery/RecoveryArcsPersistenceT177C4Base.mqh")
workflow = read("../.github/workflows/verify-current.yml")

checks: list[tuple[bool, str]] = []


def ck(condition: bool, name: str) -> None:
    checks.append((condition, name))


ck(all(token in policy for token in (
    "RECOVERY_REENTRY_WAIT_RESET", "RECOVERY_REENTRY_ARMED",
    "RECOVERY_REENTRY_TRIGGER_PENDING", "RECOVERY_REENTRY_EXHAUSTED",
)), "explicit persisted re-entry phases")
ck("Recovery_T1719ResetHitPure" in policy and
   "Recovery_T1719ReturnHitPure" in policy,
   "two-stage BUY/SELL tick-space geometry")
ck("Recovery_T1719BlocksCoreDcaPure" in policy and
   "Recovery_T1719BlocksCorePyramidAddPure" in policy and
   "Recovery_T1719AllowsCorePyramidAddPure" in policy,
   "independent DCA and Pyramid ADD policy gates")
ck("phase == RECOVERY_REENTRY_WAIT_RESET" in policy and
   "phase == RECOVERY_REENTRY_ARMED" in policy and
   "return phase == RECOVERY_REENTRY_TRIGGER_PENDING ||" in policy,
   "WAIT/ARMED block DCA but remain absent from Pyramid ADD block")
ck("BD_T1719_REENTRY_PERSIST_VERSION 1" in persist and
   "BlackDragon_Recovery_ReentryV1_" in persist and
   "FileMove(" in persist,
   "separate v1 atomic persistence")
ck("#define BD_ARCS_PERSIST_VERSION 4" in arcs_persist,
   "ARCS persistence stays at schema v4")
ck(re.search(r"input\s+int\s+MaxRecoveryReentryCycles_\s*=\s*2\s*;", config) is not None,
   "owner-facing outer-cycle cap defaults to two")
ck("RecoveryReentryBufferPips_ <= 0.0" in config and
   "MaxRecoveryReentryCycles_ > 20" in config,
   "enabled re-entry buffer and cap validated")
ck("AggregateChainCashT1719" in stack and
   "ExpectedProtectiveCloseT1719" in stack,
   "chain-level cash and exact protective identity")
ck("RECOVERY_REENTRY_COLLECTING" in stack and
   "Recovery_ArcsTotalHedgeUnits(dir,m_volumeStep)==0" in stack,
   "multi-child close collection waits for zero Hedge")
ck("SaveReentryT1719" in stack and
   stack.find("RECOVERY_REENTRY_TRIGGER_PENDING") < stack.find("ResetForReentry(dir)"),
   "trigger intent is durable before ARCS generation reset")
ck(re.search(r"StartGeneration\(dir,\s*ctx\.now,\s*why\)", stack) is not None and
   "m_dir[di].generationCount=0" in stack,
   "fresh G1 delegates to current Hedge Pyramid scheduler")
ck("T1719BlocksCoreDca" in engine and
   "T1719BlocksCorePyramidAdd" in engine and
   "T1719AllowsCorePyramidAdd" in engine,
   "Recovery engine exposes distinct admission APIs")
ck("m_recovery.T1719BlocksCoreDca(recoveryDir)" in dca,
   "Core DCA calls the T17.19 gate")
ck(all("m_recovery.T1719BlocksCorePyramidAdd" in source and
       "allowPyramidAddBuy" in source and "allowPyramidAddSell" in source
       for source in (strategy, strategy_base)),
   "both Strategy lineages disable only Pyramid ADD, never Drive/Peel")
core_pyramid = read("Include/BlackDragon/Pyramid/CorePyramidT1713.mqh")
ck("recovery.T1719AllowsCorePyramidAdd(recoveryDir)" in core_pyramid and
   "return true;" in core_pyramid,
   "WAIT_RESET/ARMED bypass legacy PAUSE_SOFT without bypassing Pyramid gates")
ck("github.event.pull_request.head.sha" in workflow and
   "t1719_reentry_model.cpp" in workflow and
   "RunT1719RecoveryReentryTests" in workflow and
   "t1719_source_contract.py" in workflow,
   "exact branch-head CI includes all T17.19 gates")

failed = [name for ok, name in checks if not ok]
for ok, name in checks:
    print(("PASS: " if ok else "FAIL: ") + name)
print(f"T17.19 source contract: {len(checks)-len(failed)} passed, {len(failed)} failed")
if failed:
    raise SystemExit(1)
print("ALL GREEN")
