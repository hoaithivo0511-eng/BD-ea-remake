from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]

def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")

recovery_types = read("Include/BlackDragon/Recovery/RecoveryTypes.mqh")
recovery_dca = read("Include/BlackDragon/Recovery/RecoveryDca.mqh")
core_pyramid = read("Include/BlackDragon/Pyramid/CorePyramid.mqh")
overlap_policy = read("Include/BlackDragon/Overlap/OverlapT177Policy.mqh")
overlap_coord = read("Include/BlackDragon/Overlap/OverlapT177Coordinator.mqh")
strategy = read("Include/BlackDragon/Strategy.mqh")
hedge_ladder = read("Include/BlackDragon/Recovery/RecoveryArcsStackT177HedgeLadderC4Base.mqh")

checks = []
def ck(ok: bool, name: str):
    checks.append((ok, name))

ck("Recovery_T1713CoreGrowthStateAllowsPure" in recovery_types,
   "shared T17.13 Recovery Core-growth state policy exists")
ck("recovery_HEDGE_BUILDING" in recovery_types and "recovery_REHEDGE_PENDING" in recovery_types,
   "T17.13 policy can classify BUILDING through REHEDGE states")
ck("Recovery_T1713CoreGrowthStateAllowsPure" in recovery_dca,
   "DCA admission uses shared T17.13 Core-growth policy")
ck("Recovery_T1713CoreGrowthStateAllowsPure" in core_pyramid,
   "Core Pyramid ADD uses shared T17.13 Core-growth policy")
ck("if(recoveryOwns || !allowAdd || !CampaignHistoryReady(dir))" not in core_pyramid,
   "Core Pyramid Drive no longer blanket-blocks ADD whenever Recovery owns side")

ck("Overlap_T1713BlocksCoreGrowthPure" in overlap_policy,
   "Overlap has a dedicated Core-growth blocking policy")
ck("overlap_T177_PAIR_ARMED" in overlap_policy,
   "Overlap policy retains durable lifecycle enum identity")
ck("Overlap_T1713MayCommitPairPure" in overlap_policy,
   "Overlap pair commit is explicitly separated from soft candidate WAIT")
ck("BlocksCoreGrowth" in overlap_coord,
   "coordinator exposes non-exclusive Core-growth admission")
ck("RouteForSide(dir, defer)" in overlap_coord,
   "coordinator preflights Recovery route before durable pair commitment")
ck("T17.13 soft-release" in overlap_coord,
   "legacy/persisted PAIR_ARMED read-only WAIT is released instead of owning side")

ck("m_overlap.BlocksCoreGrowth(BD_DIR_BUY)" in strategy and
   "m_overlap.BlocksCoreGrowth(BD_DIR_SELL)" in strategy,
   "Strategy gates DCA/Core Pyramid only on actual Overlap mutation/reconcile")
ck("t1713coreblock" in strategy,
   "Strategy journals explicit Core-growth blocker diagnostics")

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
