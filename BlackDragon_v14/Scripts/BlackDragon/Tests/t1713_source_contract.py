from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]

def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")

policy = read("Include/BlackDragon/Recovery/RecoveryT1713ConcurrencyPolicy.mqh")
recovery_dca = read("Include/BlackDragon/Recovery/RecoveryDcaT1713.mqh")
core_pyramid = read("Include/BlackDragon/Pyramid/CorePyramidT1713.mqh")
overlap_policy = read("Include/BlackDragon/Overlap/OverlapT177Policy.mqh")
overlap_coord = read("Include/BlackDragon/Overlap/OverlapT177Coordinator.mqh")
strategy_adapter = read("Include/BlackDragon/StrategyT1713.mqh")
expert = read("Experts/BlackDragon/BlackDragon.mq5")
hedge_ladder = read("Include/BlackDragon/Recovery/RecoveryArcsStackT177HedgeLadderC4Base.mqh")

checks = []
def ck(ok: bool, name: str):
    checks.append((ok, name))

ck("Recovery_T1713CoreGrowthStateAllowsPure" in policy,
   "shared T17.13 Recovery Core-growth state policy exists")
ck("recovery_HEDGE_BUILDING" in policy and "recovery_REHEDGE_PENDING" in policy,
   "T17.13 policy classifies BUILDING through REHEDGE states")
ck("Recovery_T1713CoreGrowthStateAllowsPure" in recovery_dca,
   "DCA admission wrapper uses shared T17.13 Core-growth policy")
ck("Recovery_T1713CoreGrowthStateAllowsPure" in core_pyramid,
   "Core Pyramid wrapper uses shared T17.13 Core-growth policy")
ck("TryAddT1713" in core_pyramid and "TryPeel" in core_pyramid,
   "Core Pyramid preserves Peel while routing ADD through T17.13 admission")
ck("if(!recoveryOwns && TryPeel" in core_pyramid,
   "Peel remains Recovery-owned fail-closed while only ADD gains concurrency")

ck("Overlap_T1713BlocksCoreGrowthPure" in overlap_policy,
   "Overlap has dedicated Core-growth blocking policy")
ck("Overlap_T1713MayCommitPairPure" in overlap_policy,
   "Overlap pair commit is separated from soft candidate WAIT")
ck("BlocksCoreGrowth" in overlap_coord,
   "coordinator exposes non-exclusive Core-growth admission")
ck("RouteForSide(dir, defer)" in overlap_coord,
   "coordinator preflights Recovery route before durable pair commitment")
ck("T17.13 soft-release" in overlap_coord,
   "persisted/armed pre-leg WAIT releases instead of owning side")
ck("t1713coreblock" in overlap_coord,
   "coordinator journals actual broker/reconcile Core-growth blocks")

ck("#define BlocksSide BlocksCoreGrowth" in strategy_adapter,
   "Strategy adapter remaps only same-side open admission to non-exclusive policy")
ck("CorePyramidT1713.mqh" in expert and
   "RecoveryDcaT1713.mqh" in expert and
   "StrategyT1713.mqh" in expert,
   "composition root loads all T17.13 wrappers")

ck("BuildExecutablePlanC4" in hedge_ladder and "Recovery_ArcsCoreUnits" in hedge_ladder and
   "Recovery_T176RebasedGenerationTargetPure" in hedge_ladder,
   "existing Hedge BUILDING path retains live-Core target rebase")

failed = [name for ok, name in checks if not ok]
for ok, name in checks:
    print(("PASS: " if ok else "FAIL: ") + name)
print(f"T17.13 source contract: {len(checks)-len(failed)} passed, {len(failed)} failed")
if failed:
    raise SystemExit(1)
print("ALL GREEN")
